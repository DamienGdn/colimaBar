//! Data model shared with the web UI, plus parsers for `docker` / `colima` CLI output.
//!
//! Every parser is pure (string in, struct out) so it can be unit-tested
//! without a Docker daemon.

use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::collections::HashMap;

/// Which runtime the app drives.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum Backend {
    /// Colima VM (macOS / Linux): start/stop + Docker inside it.
    Colima,
    /// Plain Docker engine (Linux native, Docker Desktop, WSL2 on Windows).
    Docker,
}

/// High-level engine state shown in the tray and the header.
#[derive(Debug, Clone, PartialEq, Serialize)]
#[serde(tag = "kind", content = "message", rename_all = "lowercase")]
pub enum EngineStatus {
    Running,
    Stopped,
    Transitioning(String),
    /// Docker CLI missing / daemon unreachable.
    Unavailable(String),
}

#[derive(Debug, Clone, Default, PartialEq, Serialize)]
pub struct ColimaInfo {
    pub name: String,
    pub status: String,
    pub cpus: u32,
    pub memory_gb: f64,
    pub disk_gb: f64,
    pub arch: String,
    pub runtime: String,
}

#[derive(Debug, Clone, Default, PartialEq, Serialize)]
pub struct Container {
    pub id: String,
    pub name: String,
    pub image: String,
    pub state: String,
    pub status: String,
    pub ports: Vec<u16>,
    pub compose_project: Option<String>,
    pub compose_service: Option<String>,
    pub health: Option<String>,
    pub restart_policy: Option<String>,
}

impl Container {
    pub fn is_running(&self) -> bool {
        self.state == "running"
    }
}

#[derive(Debug, Clone, Default, PartialEq, Serialize)]
pub struct Stats {
    pub cpu_percent: f64,
    pub mem_used_bytes: f64,
    pub mem_limit_bytes: f64,
}

#[derive(Debug, Clone, Default, PartialEq, Serialize)]
pub struct Usage {
    pub cpu_percent: f64,
    pub mem_used_bytes: f64,
    pub mem_total_bytes: f64,
    pub ncpu: u32,
}

#[derive(Debug, Clone, Default, PartialEq, Serialize)]
pub struct Image {
    pub id: String,
    pub repository: String,
    pub tag: String,
    pub size: String,
    pub created: String,
}

#[derive(Debug, Clone, Default, PartialEq, Serialize)]
pub struct Volume {
    pub name: String,
    pub driver: String,
    pub containers: Vec<String>,
}

#[derive(Debug, Clone, Default, PartialEq, Serialize)]
pub struct Network {
    pub id: String,
    pub name: String,
    pub driver: String,
    pub scope: String,
}

/// Everything the UI needs after one polling cycle.
#[derive(Debug, Clone, Serialize)]
pub struct Snapshot {
    pub backend: Backend,
    pub platform: &'static str,
    pub status: EngineStatus,
    pub colima: Option<ColimaInfo>,
    pub containers: Vec<Container>,
    pub stats: HashMap<String, Stats>,
    pub usage: Option<Usage>,
    pub portainer: bool,
    pub docker_command: String,
    pub last_error: Option<String>,
    pub updated_at: u64,
}

impl Snapshot {
    pub fn empty(backend: Backend, docker_command: String) -> Self {
        Snapshot {
            backend,
            platform: std::env::consts::OS,
            status: EngineStatus::Transitioning(String::new()),
            colima: None,
            containers: vec![],
            stats: HashMap::new(),
            usage: None,
            portainer: false,
            docker_command,
            last_error: None,
            updated_at: 0,
        }
    }

    pub fn running_count(&self) -> usize {
        self.containers.iter().filter(|c| c.is_running()).count()
    }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Iterates over NDJSON (one JSON object per line); also accepts a single JSON
/// array or object, which some CLI versions print instead.
fn json_objects(output: &str) -> Vec<Value> {
    let trimmed = output.trim();
    if trimmed.starts_with('[') {
        if let Ok(Value::Array(items)) = serde_json::from_str::<Value>(trimmed) {
            return items;
        }
    }
    trimmed
        .lines()
        .filter_map(|l| serde_json::from_str::<Value>(l.trim()).ok())
        .filter(|v| v.is_object())
        .collect()
}

fn s(v: &Value, key: &str) -> String {
    match v.get(key) {
        Some(Value::String(x)) => x.clone(),
        Some(Value::Number(n)) => n.to_string(),
        _ => String::new(),
    }
}

/// "12.34%" -> 12.34
pub fn parse_percent(text: &str) -> f64 {
    text.trim()
        .trim_end_matches('%')
        .trim()
        .parse()
        .unwrap_or(0.0)
}

/// "44.5MiB", "1.9GiB", "512kB", "1.2GB" -> bytes
pub fn parse_size(text: &str) -> f64 {
    let t = text.trim();
    let split = t
        .find(|c: char| !(c.is_ascii_digit() || c == '.'))
        .unwrap_or(t.len());
    let (num, unit) = t.split_at(split);
    let n: f64 = num.parse().unwrap_or(0.0);
    let mult = match unit.trim().to_ascii_lowercase().as_str() {
        "" | "b" => 1.0,
        "kib" => 1024.0,
        "kb" | "k" => 1000.0,
        "mib" => 1024.0 * 1024.0,
        "mb" | "m" => 1000.0 * 1000.0,
        "gib" => 1024.0 * 1024.0 * 1024.0,
        "gb" | "g" => 1000.0 * 1000.0 * 1000.0,
        "tib" => 1024f64.powi(4),
        "tb" | "t" => 1000f64.powi(4),
        _ => 1.0,
    };
    n * mult
}

/// Host ports from the `Ports` column, e.g.
/// "0.0.0.0:5433->5432/tcp, :::5433->5432/tcp, 9000/tcp" -> [5433]
pub fn parse_host_ports(ports: &str) -> Vec<u16> {
    let mut out: Vec<u16> = Vec::new();
    for part in ports.split(',') {
        let Some((host, _)) = part.trim().split_once("->") else {
            continue;
        };
        let port_str = host.rsplit(':').next().unwrap_or("");
        // Ranges like 0.0.0.0:8000-8002->8000-8002/tcp: keep the first port.
        let first = port_str.split('-').next().unwrap_or("");
        if let Ok(p) = first.parse::<u16>() {
            if !out.contains(&p) {
                out.push(p);
            }
        }
    }
    out
}

/// "com.docker.compose.project=web,com.docker.compose.service=db" -> map
pub fn parse_labels(labels: &str) -> HashMap<String, String> {
    labels
        .split(',')
        .filter_map(|kv| kv.split_once('='))
        .map(|(k, v)| (k.trim().to_string(), v.trim().to_string()))
        .collect()
}

/// Health from a status string: "Up 2 minutes (healthy)" -> Some("healthy")
pub fn parse_health(status: &str) -> Option<String> {
    for h in ["unhealthy", "healthy", "health: starting"] {
        if status.contains(&format!("({h})")) {
            return Some(if h == "health: starting" {
                "starting".into()
            } else {
                h.into()
            });
        }
    }
    None
}

// ---------------------------------------------------------------------------
// Parsers
// ---------------------------------------------------------------------------

/// `colima list --json` (NDJSON). Returns the entry for `profile`, or the
/// only entry when the output holds a single one.
pub fn parse_colima_list(output: &str, profile: &str) -> Option<ColimaInfo> {
    let entries: Vec<ColimaInfo> = json_objects(output)
        .iter()
        .map(|v| ColimaInfo {
            name: s(v, "name"),
            status: s(v, "status"),
            cpus: v.get("cpus").and_then(Value::as_u64).unwrap_or(0) as u32,
            memory_gb: v.get("memory").and_then(Value::as_f64).unwrap_or(0.0) / 1024f64.powi(3),
            disk_gb: v.get("disk").and_then(Value::as_f64).unwrap_or(0.0) / 1024f64.powi(3),
            arch: s(v, "arch"),
            runtime: s(v, "runtime"),
        })
        .collect();
    if let Some(e) = entries.iter().find(|e| e.name == profile) {
        return Some(e.clone());
    }
    if entries.len() == 1 {
        return entries.into_iter().next();
    }
    None
}

/// All profile names from `colima list --json`.
pub fn parse_colima_profiles(output: &str) -> Vec<String> {
    let names: Vec<String> = json_objects(output)
        .iter()
        .map(|v| s(v, "name"))
        .filter(|n| !n.is_empty())
        .collect();
    if names.is_empty() {
        vec!["default".into()]
    } else {
        names
    }
}

/// `docker ps -a --format '{{json .}}'`
pub fn parse_containers(output: &str) -> Vec<Container> {
    json_objects(output)
        .iter()
        .map(|v| {
            let labels = parse_labels(&s(v, "Labels"));
            let status = s(v, "Status");
            let name = s(v, "Names").split(',').next().unwrap_or("").to_string();
            Container {
                id: s(v, "ID"),
                name,
                image: s(v, "Image"),
                state: s(v, "State").to_lowercase(),
                health: parse_health(&status),
                status,
                ports: parse_host_ports(&s(v, "Ports")),
                compose_project: labels.get("com.docker.compose.project").cloned(),
                compose_service: labels.get("com.docker.compose.service").cloned(),
                restart_policy: None,
            }
        })
        .collect()
}

/// `docker stats --no-stream --format '{{json .}}'` -> name -> stats
pub fn parse_stats(output: &str) -> HashMap<String, Stats> {
    json_objects(output)
        .iter()
        .map(|v| {
            let mem = s(v, "MemUsage");
            let (used, limit) = mem.split_once('/').unwrap_or((mem.as_str(), "0"));
            (
                s(v, "Name"),
                Stats {
                    cpu_percent: parse_percent(&s(v, "CPUPerc")),
                    mem_used_bytes: parse_size(used),
                    mem_limit_bytes: parse_size(limit),
                },
            )
        })
        .filter(|(name, _)| !name.is_empty())
        .collect()
}

/// `docker inspect --format '{{.Name}}\t{{.HostConfig.RestartPolicy.Name}}' ids…`
pub fn parse_restart_policies(output: &str) -> HashMap<String, String> {
    output
        .lines()
        .filter_map(|l| l.split_once('\t'))
        .map(|(n, p)| {
            (
                n.trim().trim_start_matches('/').to_string(),
                p.trim().to_string(),
            )
        })
        .filter(|(n, _)| !n.is_empty())
        .collect()
}

/// `docker info --format '{{.NCPU}}\t{{.MemTotal}}'`
pub fn parse_info(output: &str) -> Option<(u32, f64)> {
    let (ncpu, mem) = output.trim().split_once('\t')?;
    Some((ncpu.trim().parse().ok()?, mem.trim().parse().ok()?))
}

/// `docker images --format '{{json .}}'`
pub fn parse_images(output: &str) -> Vec<Image> {
    json_objects(output)
        .iter()
        .map(|v| Image {
            id: s(v, "ID"),
            repository: s(v, "Repository"),
            tag: s(v, "Tag"),
            size: s(v, "Size"),
            created: s(v, "CreatedSince"),
        })
        .collect()
}

/// `docker volume ls --format '{{json .}}'` + `docker ps -a --format '{{.Names}}\t{{.Mounts}}'`
pub fn parse_volumes(ls_output: &str, mounts_output: &str) -> Vec<Volume> {
    let mut usage: HashMap<String, Vec<String>> = HashMap::new();
    for line in mounts_output.lines() {
        let Some((container, mounts)) = line.split_once('\t') else {
            continue;
        };
        for m in mounts.split(',').map(str::trim).filter(|m| !m.is_empty()) {
            usage
                .entry(m.to_string())
                .or_default()
                .push(container.trim().to_string());
        }
    }
    json_objects(ls_output)
        .iter()
        .map(|v| {
            let name = s(v, "Name");
            // `{{.Mounts}}` truncates long names to 15 chars + "…"
            let containers = usage
                .iter()
                .filter(|(m, _)| {
                    *m == &name || (m.ends_with('…') && name.starts_with(m.trim_end_matches('…')))
                })
                .flat_map(|(_, c)| c.clone())
                .collect();
            Volume {
                driver: s(v, "Driver"),
                name,
                containers,
            }
        })
        .collect()
}

/// `docker network ls --format '{{json .}}'`
pub fn parse_networks(output: &str) -> Vec<Network> {
    json_objects(output)
        .iter()
        .map(|v| Network {
            id: s(v, "ID"),
            name: s(v, "Name"),
            driver: s(v, "Driver"),
            scope: s(v, "Scope"),
        })
        .collect()
}

/// `docker inspect --format '{{json .Config.Env}}'`
pub fn parse_env(output: &str) -> Vec<String> {
    serde_json::from_str::<Vec<String>>(output.trim()).unwrap_or_default()
}

/// `docker ps -a --filter name=^portainer$ --format '{{.Names}}'`
pub fn portainer_exists(output: &str) -> bool {
    output
        .lines()
        .map(str::trim)
        .any(|l| l == "portainer" || l == "/portainer")
}

/// Settings persisted in the app config dir.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(default)]
pub struct Settings {
    /// "system" | "fr" | "en"
    pub language: String,
    /// "fast" | "normal" | "slow"
    pub polling: String,
    /// Override for the docker CLI, e.g. `wsl -e docker` or `podman`. Empty = auto.
    pub docker_command: String,
    /// Use Colima when it is installed (ignored on Windows).
    pub use_colima: bool,
    pub colima_profile: String,
    pub cpus: u32,
    pub memory_gb: u32,
    pub disk_gb: u32,
    pub auto_start_engine: bool,
    pub show_all_containers: bool,
    pub resource_alerts: bool,
    /// Keep the window hidden at launch (tray only). Off by default because
    /// some Linux desktops (vanilla GNOME) have no tray area.
    pub start_hidden: bool,
}

impl Default for Settings {
    fn default() -> Self {
        Settings {
            language: "system".into(),
            polling: "normal".into(),
            docker_command: String::new(),
            use_colima: true,
            colima_profile: "default".into(),
            cpus: 2,
            memory_gb: 4,
            disk_gb: 60,
            auto_start_engine: false,
            show_all_containers: true,
            resource_alerts: true,
            start_hidden: false,
        }
    }
}

impl Settings {
    /// "fr" or "en", resolving "system" from the OS locale.
    pub fn lang(&self) -> &'static str {
        match self.language.as_str() {
            "fr" => "fr",
            "en" => "en",
            _ => {
                let loc = sys_locale::get_locale().unwrap_or_default().to_lowercase();
                if loc.starts_with("fr") {
                    "fr"
                } else {
                    "en"
                }
            }
        }
    }

    /// Picks the French or English string for the current language.
    pub fn t(&self, fr: &str, en: &str) -> String {
        if self.lang() == "fr" {
            fr.to_string()
        } else {
            en.to_string()
        }
    }

    /// Polling interval in seconds (engine running, engine stopped).
    pub fn intervals(&self) -> (u64, u64) {
        match self.polling.as_str() {
            "fast" => (2, 10),
            "slow" => (15, 60),
            _ => (5, 30),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn percent_and_size() {
        assert_eq!(parse_percent("12.5%"), 12.5);
        assert_eq!(parse_percent("--"), 0.0);
        assert_eq!(parse_size("44MiB"), 44.0 * 1024.0 * 1024.0);
        assert_eq!(parse_size("1.5GiB"), 1.5 * 1024f64.powi(3));
        assert_eq!(parse_size("512kB"), 512_000.0);
        assert_eq!(parse_size("0B"), 0.0);
    }

    #[test]
    fn host_ports() {
        assert_eq!(
            parse_host_ports("0.0.0.0:5433->5432/tcp, :::5433->5432/tcp"),
            vec![5433]
        );
        assert_eq!(
            parse_host_ports("0.0.0.0:8000->8000/tcp, 0.0.0.0:9443->9443/tcp, 9000/tcp"),
            vec![8000, 9443]
        );
        assert_eq!(
            parse_host_ports("0.0.0.0:8000-8002->8000-8002/tcp"),
            vec![8000]
        );
        assert!(parse_host_ports("").is_empty());
        assert!(parse_host_ports("5432/tcp").is_empty());
    }

    #[test]
    fn health() {
        assert_eq!(
            parse_health("Up 2 minutes (healthy)").as_deref(),
            Some("healthy")
        );
        assert_eq!(
            parse_health("Up 1 second (unhealthy)").as_deref(),
            Some("unhealthy")
        );
        assert_eq!(
            parse_health("Up 3 seconds (health: starting)").as_deref(),
            Some("starting")
        );
        assert_eq!(parse_health("Up 2 minutes"), None);
    }

    #[test]
    fn colima_list_ndjson() {
        let out = r#"{"name":"default","status":"Running","arch":"aarch64","cpus":2,"memory":4294967296,"disk":64424509440,"runtime":"docker"}
{"name":"dev","status":"Stopped","arch":"aarch64","cpus":4,"memory":8589934592,"disk":64424509440,"runtime":"docker"}"#;
        let d = parse_colima_list(out, "default").unwrap();
        assert_eq!(d.status, "Running");
        assert_eq!(d.cpus, 2);
        assert_eq!(d.memory_gb, 4.0);
        assert_eq!(d.disk_gb, 60.0);
        assert_eq!(parse_colima_list(out, "dev").unwrap().cpus, 4);
        assert!(parse_colima_list(out, "nope").is_none());
        assert_eq!(parse_colima_profiles(out), vec!["default", "dev"]);
        assert_eq!(parse_colima_profiles(""), vec!["default"]);
    }

    #[test]
    fn containers() {
        let out = r#"{"ID":"abc","Image":"postgres:15-alpine","Labels":"com.docker.compose.project=shop,com.docker.compose.service=db","Names":"shop-db-1","Ports":"0.0.0.0:5433->5432/tcp","State":"running","Status":"Up 2 minutes (healthy)"}
{"ID":"def","Image":"nginx:latest","Labels":"","Names":"web","Ports":"","State":"exited","Status":"Exited (0) 2 hours ago"}"#;
        let c = parse_containers(out);
        assert_eq!(c.len(), 2);
        assert_eq!(c[0].name, "shop-db-1");
        assert!(c[0].is_running());
        assert_eq!(c[0].ports, vec![5433]);
        assert_eq!(c[0].compose_project.as_deref(), Some("shop"));
        assert_eq!(c[0].compose_service.as_deref(), Some("db"));
        assert_eq!(c[0].health.as_deref(), Some("healthy"));
        assert!(!c[1].is_running());
        assert_eq!(c[1].compose_project, None);
        assert!(parse_containers("").is_empty());
    }

    #[test]
    fn stats() {
        let out = r#"{"BlockIO":"0B / 0B","CPUPerc":"1.50%","Container":"abc","ID":"abc","MemPerc":"2.21%","MemUsage":"44MiB / 1.9GiB","Name":"shop-db-1","NetIO":"1kB / 0B","PIDs":"6"}"#;
        let st = parse_stats(out);
        let s = &st["shop-db-1"];
        assert_eq!(s.cpu_percent, 1.5);
        assert_eq!(s.mem_used_bytes, 44.0 * 1024.0 * 1024.0);
        assert!((s.mem_limit_bytes - 1.9 * 1024f64.powi(3)).abs() < 1.0);
    }

    #[test]
    fn restart_policies_and_info() {
        let p = parse_restart_policies("/web\talways\n/db\t\n");
        assert_eq!(p["web"], "always");
        assert_eq!(p["db"], "");
        assert_eq!(parse_info("4\t8241434624\n"), Some((4, 8241434624.0)));
        assert_eq!(parse_info("garbage"), None);
    }

    #[test]
    fn images_volumes_networks_env() {
        let imgs = parse_images(
            r#"{"CreatedSince":"2 weeks ago","ID":"sha1","Repository":"nginx","Size":"192MB","Tag":"latest"}"#,
        );
        assert_eq!(imgs[0].repository, "nginx");
        assert_eq!(imgs[0].size, "192MB");

        let vols = parse_volumes(
            "{\"Driver\":\"local\",\"Name\":\"pgdata\"}\n{\"Driver\":\"local\",\"Name\":\"unused\"}",
            "shop-db-1\tpgdata\nweb\t/host/path\n",
        );
        assert_eq!(vols[0].containers, vec!["shop-db-1"]);
        assert!(vols[1].containers.is_empty());

        let nets =
            parse_networks(r#"{"Driver":"bridge","ID":"n1","Name":"bridge","Scope":"local"}"#);
        assert_eq!(nets[0].driver, "bridge");

        assert_eq!(parse_env(r#"["A=1","B=two"]"#), vec!["A=1", "B=two"]);
        assert!(parse_env("null").is_empty());
    }

    #[test]
    fn portainer() {
        assert!(portainer_exists("portainer\n"));
        assert!(!portainer_exists("portainer-agent\n"));
    }

    #[test]
    fn settings_defaults_and_partial_json() {
        let s: Settings = serde_json::from_str(r#"{"polling":"fast"}"#).unwrap();
        assert_eq!(s.intervals(), (2, 10));
        assert_eq!(s.colima_profile, "default");
        assert_eq!(Settings::default().intervals(), (5, 30));
    }
}
