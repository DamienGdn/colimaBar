//! Runs `docker` / `colima` commands and builds [`Snapshot`]s.
//!
//! Backend selection:
//! - macOS / Linux with `colima` installed (and enabled in settings): Colima.
//! - Otherwise: plain Docker. On Windows the docker CLI is used directly
//!   (Docker Desktop / Docker Engine with a Windows CLI), falling back to
//!   `wsl -e docker` when only WSL2 has Docker. Users can override the command.

use crate::model::*;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::time::{SystemTime, UNIX_EPOCH};

#[cfg(windows)]
use std::os::windows::process::CommandExt;

/// Avoids flashing a console window for every CLI call on Windows.
#[cfg(windows)]
const CREATE_NO_WINDOW: u32 = 0x0800_0000;

#[derive(Debug, Clone)]
pub struct Engine {
    pub backend: Backend,
    /// Program + leading args, e.g. ["docker"] or ["wsl", "-e", "docker"].
    pub docker: Vec<String>,
    pub colima: Option<PathBuf>,
    pub profile: String,
}

#[derive(Debug)]
pub struct CmdOutput {
    pub ok: bool,
    pub stdout: String,
    pub stderr: String,
}

impl CmdOutput {
    pub fn into_result(self) -> Result<String, String> {
        if self.ok {
            Ok(self.stdout)
        } else {
            let msg = if self.stderr.trim().is_empty() {
                self.stdout
            } else {
                self.stderr
            };
            Err(msg
                .trim()
                .lines()
                .last()
                .unwrap_or("command failed")
                .to_string())
        }
    }
}

/// Builds a `Command` with the platform tweaks we always want.
pub fn command(program: impl AsRef<std::ffi::OsStr>) -> Command {
    #[allow(unused_mut)]
    let mut cmd = Command::new(program);
    #[cfg(windows)]
    cmd.creation_flags(CREATE_NO_WINDOW);
    cmd
}

pub fn run(program: &Path, args: &[&str]) -> CmdOutput {
    match command(program).args(args).stdin(Stdio::null()).output() {
        Ok(o) => CmdOutput {
            ok: o.status.success(),
            stdout: String::from_utf8_lossy(&o.stdout).into_owned(),
            stderr: String::from_utf8_lossy(&o.stderr).into_owned(),
        },
        Err(e) => CmdOutput {
            ok: false,
            stdout: String::new(),
            stderr: e.to_string(),
        },
    }
}

/// Finds an executable in PATH plus the usual Homebrew / user locations
/// (GUI apps on macOS/Linux often start with a minimal PATH).
pub fn which(name: &str) -> Option<PathBuf> {
    let exts: Vec<String> = if cfg!(windows) {
        std::env::var("PATHEXT")
            .unwrap_or_else(|_| ".EXE;.CMD;.BAT".into())
            .split(';')
            .map(|e| e.to_ascii_lowercase())
            .chain(std::iter::once(String::new()))
            .collect()
    } else {
        vec![String::new()]
    };
    let mut dirs: Vec<PathBuf> = std::env::var_os("PATH")
        .map(|p| std::env::split_paths(&p).collect())
        .unwrap_or_default();
    if !cfg!(windows) {
        for d in [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/home/linuxbrew/.linuxbrew/bin",
        ] {
            dirs.push(PathBuf::from(d));
        }
        if let Some(home) = std::env::var_os("HOME") {
            dirs.push(PathBuf::from(&home).join(".local/bin"));
        }
    } else if let Some(pf) = std::env::var_os("ProgramFiles") {
        dirs.push(PathBuf::from(pf).join("Docker\\Docker\\resources\\bin"));
    }
    for dir in dirs {
        for ext in &exts {
            let candidate = dir.join(format!("{name}{ext}"));
            if candidate.is_file() {
                return Some(candidate);
            }
        }
    }
    None
}

fn now_secs() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0)
}

impl Engine {
    pub fn detect(settings: &Settings) -> Engine {
        let docker: Vec<String> = if !settings.docker_command.trim().is_empty() {
            settings
                .docker_command
                .split_whitespace()
                .map(String::from)
                .collect()
        } else if let Some(p) = which("docker") {
            vec![p.to_string_lossy().into_owned()]
        } else if cfg!(windows) && which("wsl").is_some() {
            vec!["wsl".into(), "-e".into(), "docker".into()]
        } else {
            vec!["docker".into()]
        };
        let colima = if cfg!(windows) || !settings.use_colima {
            None
        } else {
            which("colima")
        };
        Engine {
            backend: if colima.is_some() {
                Backend::Colima
            } else {
                Backend::Docker
            },
            docker,
            colima,
            profile: if settings.colima_profile.trim().is_empty() {
                "default".into()
            } else {
                settings.colima_profile.trim().to_string()
            },
        }
    }

    pub fn docker_command_label(&self) -> String {
        self.docker
            .iter()
            .map(|p| {
                Path::new(p)
                    .file_stem()
                    .map(|s| s.to_string_lossy().into_owned())
                    .unwrap_or_else(|| p.clone())
            })
            .collect::<Vec<_>>()
            .join(" ")
    }

    /// Runs `docker <args>` through the configured command (incl. WSL prefix).
    pub fn docker(&self, args: &[&str]) -> CmdOutput {
        let (program, prefix) = self
            .docker
            .split_first()
            .expect("docker command is never empty");
        let mut all: Vec<&str> = prefix.iter().map(String::as_str).collect();
        all.extend_from_slice(args);
        run(Path::new(program), &all)
    }

    pub fn colima(&self, args: &[&str]) -> CmdOutput {
        match &self.colima {
            Some(p) => run(p, args),
            None => CmdOutput {
                ok: false,
                stdout: String::new(),
                stderr: "colima not installed".into(),
            },
        }
    }

    /// Full command line for running docker in an external terminal.
    pub fn docker_argv(&self, args: &[&str]) -> Vec<String> {
        let mut v = self.docker.clone();
        v.extend(args.iter().map(|s| s.to_string()));
        v
    }

    // -----------------------------------------------------------------------
    // Polling
    // -----------------------------------------------------------------------

    pub fn snapshot(&self) -> Snapshot {
        let mut snap = Snapshot::empty(self.backend, self.docker_command_label());
        snap.updated_at = now_secs();

        if self.backend == Backend::Colima {
            let list = self.colima(&["list", "--json"]);
            let info = if list.ok {
                parse_colima_list(&list.stdout, &self.profile)
            } else {
                None
            };
            let running = info
                .as_ref()
                .map(|i| i.status.eq_ignore_ascii_case("running"))
                .unwrap_or(false);
            snap.colima = info;
            if !running {
                snap.status = EngineStatus::Stopped;
                return snap;
            }
        }

        // Daemon reachable?
        let info = self.docker(&["info", "--format", "{{.NCPU}}\t{{.MemTotal}}"]);
        if !info.ok {
            let msg = info.into_result().err().unwrap_or_default();
            snap.status = if self.backend == Backend::Colima {
                EngineStatus::Transitioning(msg)
            } else {
                EngineStatus::Unavailable(msg)
            };
            return snap;
        }
        snap.status = EngineStatus::Running;
        let (ncpu, mem_total) = parse_info(&info.stdout).unwrap_or((0, 0.0));

        let ps = self.docker(&["ps", "-a", "--format", "{{json .}}"]);
        if !ps.ok {
            snap.last_error = ps.into_result().err();
            return snap;
        }
        snap.containers = parse_containers(&ps.stdout);
        snap.portainer = snap.containers.iter().any(|c| c.name == "portainer");

        if !snap.containers.is_empty() {
            let ids: Vec<&str> = snap.containers.iter().map(|c| c.id.as_str()).collect();
            let mut args = vec![
                "inspect",
                "--format",
                "{{.Name}}\t{{.HostConfig.RestartPolicy.Name}}",
            ];
            args.extend(ids);
            let policies = parse_restart_policies(&self.docker(&args).stdout);
            for c in &mut snap.containers {
                c.restart_policy = policies.get(&c.name).cloned();
            }
        }

        if snap.running_count() > 0 {
            let st = self.docker(&["stats", "--no-stream", "--format", "{{json .}}"]);
            if st.ok {
                snap.stats = parse_stats(&st.stdout);
            }
        }
        let cpu: f64 = snap.stats.values().map(|s| s.cpu_percent).sum();
        let mem: f64 = snap.stats.values().map(|s| s.mem_used_bytes).sum();
        snap.usage = Some(Usage {
            cpu_percent: cpu,
            mem_used_bytes: mem,
            mem_total_bytes: mem_total,
            ncpu,
        });
        snap
    }

    // -----------------------------------------------------------------------
    // Engine lifecycle (Colima only)
    // -----------------------------------------------------------------------

    pub fn start_engine(&self, s: &Settings) -> Result<(), String> {
        if self.backend != Backend::Colima {
            return Err("Start/stop is only available with Colima".into());
        }
        let (cpu, mem, disk) = (
            s.cpus.to_string(),
            s.memory_gb.to_string(),
            s.disk_gb.to_string(),
        );
        let mut args = vec!["start"];
        if self.profile != "default" {
            args.push(&self.profile);
        }
        args.extend(["--cpu", &cpu, "--memory", &mem, "--disk", &disk]);
        self.colima(&args).into_result()?;
        if self.portainer_exists() {
            let _ = self.docker(&["start", "portainer"]);
        }
        Ok(())
    }

    pub fn stop_engine(&self) -> Result<(), String> {
        if self.backend != Backend::Colima {
            return Err("Start/stop is only available with Colima".into());
        }
        let mut args = vec!["stop"];
        if self.profile != "default" {
            args.push(&self.profile);
        }
        self.colima(&args).into_result().map(|_| ())
    }

    pub fn profiles(&self) -> Vec<String> {
        if self.backend != Backend::Colima {
            return vec![];
        }
        parse_colima_profiles(&self.colima(&["list", "--json"]).stdout)
    }

    // -----------------------------------------------------------------------
    // Docker resources
    // -----------------------------------------------------------------------

    pub fn container_action(&self, name: &str, action: &str) -> Result<(), String> {
        match action {
            "start" | "stop" | "restart" | "pause" | "unpause" => {
                self.docker(&[action, name]).into_result().map(|_| ())
            }
            "remove" => self.docker(&["rm", "-f", name]).into_result().map(|_| ()),
            _ => Err(format!("unknown action: {action}")),
        }
    }

    pub fn set_restart_policy(&self, name: &str, policy: &str) -> Result<(), String> {
        if !["no", "always", "on-failure", "unless-stopped"].contains(&policy) {
            return Err(format!("invalid restart policy: {policy}"));
        }
        let flag = format!("--restart={policy}");
        self.docker(&["update", &flag, name])
            .into_result()
            .map(|_| ())
    }

    pub fn env(&self, name: &str) -> Result<Vec<String>, String> {
        let out = self
            .docker(&["inspect", "--format", "{{json .Config.Env}}", name])
            .into_result()?;
        Ok(parse_env(&out))
    }

    pub fn inspect(&self, name: &str) -> Result<String, String> {
        self.docker(&["inspect", name]).into_result()
    }

    pub fn images(&self) -> Result<Vec<Image>, String> {
        Ok(parse_images(
            &self
                .docker(&["images", "--format", "{{json .}}"])
                .into_result()?,
        ))
    }

    pub fn remove_image(&self, id: &str) -> Result<(), String> {
        self.docker(&["rmi", id]).into_result().map(|_| ())
    }

    pub fn pull_image(&self, name: &str) -> Result<(), String> {
        self.docker(&["pull", name]).into_result().map(|_| ())
    }

    pub fn volumes(&self) -> Result<Vec<Volume>, String> {
        let ls = self
            .docker(&["volume", "ls", "--format", "{{json .}}"])
            .into_result()?;
        let mounts = self
            .docker(&["ps", "-a", "--format", "{{.Names}}\t{{.Mounts}}"])
            .stdout;
        Ok(parse_volumes(&ls, &mounts))
    }

    pub fn networks(&self) -> Result<Vec<Network>, String> {
        Ok(parse_networks(
            &self
                .docker(&["network", "ls", "--format", "{{json .}}"])
                .into_result()?,
        ))
    }

    pub fn prune(&self, what: &str) -> Result<String, String> {
        match what {
            "system" => self.docker(&["system", "prune", "-f"]).into_result(),
            "volumes" => self.docker(&["volume", "prune", "-f"]).into_result(),
            "networks" => self.docker(&["network", "prune", "-f"]).into_result(),
            "images" => self.docker(&["image", "prune", "-f"]).into_result(),
            _ => Err(format!("unknown prune target: {what}")),
        }
    }

    pub fn portainer_exists(&self) -> bool {
        portainer_exists(
            &self
                .docker(&[
                    "ps",
                    "-a",
                    "--filter",
                    "name=^portainer$",
                    "--format",
                    "{{.Names}}",
                ])
                .stdout,
        )
    }

    pub fn install_portainer(&self) -> Result<(), String> {
        self.docker(&[
            "run",
            "-d",
            "-p",
            "8000:8000",
            "-p",
            "9443:9443",
            "--name",
            "portainer",
            "--restart=always",
            "-v",
            "/var/run/docker.sock:/var/run/docker.sock",
            "-v",
            "portainer_data:/data",
            "portainer/portainer-ce:latest",
        ])
        .into_result()
        .map(|_| ())
    }
}

/// Opens an interactive `docker exec` session in the user's terminal.
#[cfg(windows)]
pub fn open_terminal(argv: &[String]) -> Result<(), String> {
    // Windows Terminal if available, else a classic console. `start` detaches it.
    let spawned = if which("wt").is_some() {
        command("cmd")
            .args(["/C", "start", "", "wt.exe"])
            .args(argv)
            .spawn()
    } else {
        command("cmd")
            .args(["/C", "start", "", "cmd", "/K"])
            .args(argv)
            .spawn()
    };
    spawned.map(|_| ()).map_err(|e| e.to_string())
}

/// Opens an interactive `docker exec` session in the user's terminal.
#[cfg(target_os = "macos")]
pub fn open_terminal(argv: &[String]) -> Result<(), String> {
    let line = argv.join(" ").replace('\\', "\\\\").replace('"', "\\\"");
    let script = format!("tell application \"Terminal\" to do script \"{line}\"");
    Command::new("osascript")
        .args(["-e", &script])
        .spawn()
        .map(|_| ())
        .map_err(|e| e.to_string())
}

/// Opens an interactive `docker exec` session in the user's terminal.
#[cfg(all(unix, not(target_os = "macos")))]
pub fn open_terminal(argv: &[String]) -> Result<(), String> {
    // (terminal, args placed before the command)
    let candidates: [(&str, &[&str]); 8] = [
        ("x-terminal-emulator", &["-e"]),
        ("gnome-terminal", &["--"]),
        ("konsole", &["-e"]),
        ("xfce4-terminal", &["-x"]),
        ("kitty", &[]),
        ("alacritty", &["-e"]),
        ("wezterm", &["start", "--"]),
        ("xterm", &["-e"]),
    ];
    for (term, pre) in candidates {
        if let Some(path) = which(term) {
            return Command::new(path)
                .args(pre)
                .args(argv)
                .spawn()
                .map(|_| ())
                .map_err(|e| e.to_string());
        }
    }
    Err(
        "No terminal emulator found (tried x-terminal-emulator, gnome-terminal, konsole, ...)"
            .into(),
    )
}
