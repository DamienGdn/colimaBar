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
