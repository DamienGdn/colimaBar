import Foundation
import ColimaBarCore

private func ctr(_ name: String, _ state: DockerContainer.ContainerState, project: String? = nil) -> DockerContainer {
    DockerContainer(id: name, name: name, state: state, status: "", image: "img", ports: "",
                    labels: project.map { "com.docker.compose.project=\($0)" } ?? "")
}

func test_groupContainers_empty() {
    let r = ContainerGrouping.group([], stats: [:])
    check(r.stacks.isEmpty, "no stacks")
    check(r.standalone.isEmpty, "no standalone")
}

func test_groupContainers_stacksAndStandalone() {
    let r = ContainerGrouping.group([ctr("web", .running, project: "shop"), ctr("db", .running, project: "shop"), ctr("solo", .running)], stats: [:])
    checkEqual(r.stacks.count, 1, "one stack")
    checkEqual(r.stacks.first?.name, "shop", "name")
    checkEqual(r.stacks.first?.containers.map { $0.name }, ["db", "web"], "sorted")
    checkEqual(r.standalone.map { $0.name }, ["solo"], "standalone")
}

func test_groupContainers_statusPartial() {
    let cs = [ctr("a", .running, project: "shop"), ctr("b", .running, project: "shop"), ctr("c", .running, project: "shop"), ctr("d", .exited, project: "shop")]
    checkEqual(ContainerGrouping.group(cs, stats: [:]).stacks.first?.status, StackStatus.partial(running: 3, total: 4), "partial")
}

func test_groupContainers_statusAllRunning() {
    let up = [ctr("a", .running, project: "p"), ctr("b", .running, project: "p")]
    checkEqual(ContainerGrouping.group(up, stats: [:]).stacks.first?.status, StackStatus.allRunning, "all running")
    let down = [ctr("a", .exited, project: "p"), ctr("b", .exited, project: "p")]
    checkEqual(ContainerGrouping.group(down, stats: [:]).stacks.first?.status, StackStatus.stopped, "stopped")
}

func test_groupContainers_missingStats() {
    let cs = [ctr("a", .running, project: "p"), ctr("b", .running, project: "p")]
    let r = ContainerGrouping.group(cs, stats: ["a": ResourceUsage(cpuPercent: 12.5, memUsedMiB: 100, memTotalGiB: 8)])
    checkEqual(r.stacks.first?.cpuPercent, 12.5, "cpu")
    checkEqual(r.stacks.first?.memUsedMiB, 100, "mem")
}

func test_metricHistory_capacity() {
    var h = MetricHistory(capacity: 3)
    for v in 1...5 { h.append(Double(v)) }
    checkEqual(h.values, [3, 4, 5], "last three")
}

func test_metricHistoryStore_prune() {
    var s = MetricHistoryStore()
    let u = ResourceUsage(cpuPercent: 1, memUsedMiB: 2, memTotalGiB: 8)
    s.record(["a": u, "b": u])
    s.record(["a": u])
    checkEqual(Array(s.cpu.keys), ["a"], "keys")
    checkEqual(s.cpu["a"]?.values.count, 2, "count")
    checkEqual(s.mem["a"]?.values.count, 2, "mem count")
}
