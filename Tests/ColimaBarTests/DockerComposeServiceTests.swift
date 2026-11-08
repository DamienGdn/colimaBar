// Tests/ColimaBarTests/DockerComposeServiceTests.swift
import Foundation
import ColimaBarCore

func test_findComposeFile_withWorkingDirAndConfigFiles() {
    let labels = "com.docker.compose.project=myapp,com.docker.compose.project.working_dir=/Users/user/myproject,com.docker.compose.project.config_files=docker-compose.yml"
    let container = DockerContainer(id: "1", name: "myapp_web_1", state: .running,
                                    status: "Up", image: "nginx", ports: "", labels: labels)
    let url = DockerComposeService.findComposeFile(for: container)
    checkEqual(url?.path, "/Users/user/myproject/docker-compose.yml",
               "findComposeFile: relative config_files resolved against working_dir")
}

func test_findComposeFile_withAbsoluteConfigFiles() {
    let labels = "com.docker.compose.project=myapp,com.docker.compose.project.working_dir=/Users/user/myproject,com.docker.compose.project.config_files=/Users/user/myproject/docker-compose.yml"
    let container = DockerContainer(id: "1", name: "myapp_web_1", state: .running,
                                    status: "Up", image: "nginx", ports: "", labels: labels)
    let url = DockerComposeService.findComposeFile(for: container)
    checkEqual(url?.path, "/Users/user/myproject/docker-compose.yml",
               "findComposeFile: absolute config_files returned as-is")
}

func test_findComposeFile_noLabels() {
    let container = DockerContainer(id: "1", name: "standalone", state: .running,
                                    status: "Up", image: "nginx", ports: "", labels: "")
    let url = DockerComposeService.findComposeFile(for: container)
    checkNil(url, "findComposeFile: nil when no compose labels")
}

func test_findComposeFile_missingWorkingDir() {
    let labels = "com.docker.compose.project=myapp,com.docker.compose.project.config_files=docker-compose.yml"
    let container = DockerContainer(id: "1", name: "myapp_web_1", state: .running,
                                    status: "Up", image: "nginx", ports: "", labels: labels)
    let url = DockerComposeService.findComposeFile(for: container)
    checkNil(url, "findComposeFile: nil when working_dir missing")
}

func test_composeProjects_groupsContainersByProject() {
    let labels1 = "com.docker.compose.project=proj1,com.docker.compose.project.working_dir=/a,com.docker.compose.project.config_files=docker-compose.yml"
    let labels2 = "com.docker.compose.project=proj1,com.docker.compose.project.working_dir=/a,com.docker.compose.project.config_files=docker-compose.yml"
    let labels3 = "com.docker.compose.project=proj2,com.docker.compose.project.working_dir=/b,com.docker.compose.project.config_files=docker-compose.yml"
    let containers = [
        DockerContainer(id: "1", name: "a1", state: .running, status: "Up", image: "n", ports: "", labels: labels1),
        DockerContainer(id: "2", name: "a2", state: .running, status: "Up", image: "n", ports: "", labels: labels2),
        DockerContainer(id: "3", name: "b1", state: .running, status: "Up", image: "n", ports: "", labels: labels3),
    ]
    let projects = DockerComposeService.listProjects(from: containers)
    checkEqual(projects.count, 2, "listProjects: 2 unique projects")
    check(projects.contains { $0.name == "proj1" }, "listProjects: proj1 present")
    check(projects.contains { $0.name == "proj2" }, "listProjects: proj2 present")
}

private func proj(_ name: String) -> ComposeProject {
    ComposeProject(name: name, workingDir: "/w/\(name)", configFile: URL(fileURLWithPath: "/w/\(name)/compose.yml"))
}

func test_composeEditorPlan_firstLoadPicksFirst() {
    let r = ComposeEditorPlan.reconcile(available: [proj("shop"), proj("blog")], loaded: nil, dirty: false)
    checkEqual(r.entries.map { $0.name }, ["blog", "shop"], "sorted")
    checkEqual(r.selection?.name, "blog", "first")
    check(r.reload, "load file")
}

func test_composeEditorPlan_emptyList() {
    let r = ComposeEditorPlan.reconcile(available: [], loaded: nil, dirty: false)
    check(r.entries.isEmpty && r.selection == nil && !r.reload, "empty state")
}

func test_composeEditorPlan_keepsLoadedProject() {
    let r = ComposeEditorPlan.reconcile(available: [proj("blog"), proj("shop")], loaded: proj("shop"), dirty: false)
    checkEqual(r.selection?.name, "shop", "kept")
    check(!r.reload, "no reload")
}

func test_composeEditorPlan_dirtyLoadedDisappears_keptDetached() {
    let r = ComposeEditorPlan.reconcile(available: [proj("blog")], loaded: proj("shop"), dirty: true)
    checkEqual(r.entries.map { $0.name }, ["blog", "shop"], "detached entry kept")
    checkEqual(r.selection?.name, "shop", "still selected")
    check(!r.reload, "edits kept")
    let empty = ComposeEditorPlan.reconcile(available: [], loaded: proj("shop"), dirty: true)
    checkEqual(empty.selection?.name, "shop", "kept even when list empties")
}

func test_composeEditorPlan_cleanLoadedDisappears_switches() {
    let r = ComposeEditorPlan.reconcile(available: [proj("blog")], loaded: proj("shop"), dirty: false)
    checkEqual(r.entries.map { $0.name }, ["blog"], "dropped")
    checkEqual(r.selection?.name, "blog", "first")
    check(r.reload, "reload")
}
