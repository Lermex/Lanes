import Foundation

public struct GraphTransition: Sendable, Hashable {
  public let fromLane: Int
  public let toLane: Int
  public let colorIndex: Int
  public let startsAtNode: Bool
}

public struct GraphRow: Sendable, Hashable {
  public let nodeLane: Int
  public let nodeColorIndex: Int
  public let incoming: [GraphTransition]
  public let outgoing: [GraphTransition]
  public let laneCount: Int
}

public struct GraphLayout: Sendable, Hashable {
  public let rows: [GraphRow]
  public let maxLaneCount: Int

  public static let empty = GraphLayout(rows: [], maxLaneCount: 0)

  public static func compute(_ commits: [Commit]) -> GraphLayout {
    var builder = Builder()
    for (index, commit) in commits.enumerated() {
      builder.process(commit, next: index + 1 < commits.count ? commits[index + 1] : nil)
    }
    return builder.finish()
  }

  private struct Lane {
    var expected: String
    var color: Int
  }

  private struct PendingTransition {
    var fromLane: Int
    var toLane: Int
    var expected: String
    var color: Int
    var startsAtNode: Bool

    var resolved: GraphTransition {
      GraphTransition(fromLane: fromLane, toLane: toLane, colorIndex: color, startsAtNode: startsAtNode)
    }
  }

  private struct Builder {
    var lanes: [Lane?] = []
    var nextColor = 0
    var nodeLanes: [Int] = []
    var nodeColors: [Int] = []
    var laneCounts: [Int] = []
    var outgoing: [[PendingTransition]] = []

    mutating func process(_ commit: Commit, next: Commit?) {
      let laneCountBefore = lanes.count
      let column = lanes.firstIndex { $0?.expected == commit.sha } ?? claimLane(expected: commit.sha, color: allocateColor())
      let nodeColor = lanes[column]?.color ?? 0
      nodeLanes.append(column)
      nodeColors.append(nodeColor)

      for index in lanes.indices where index != column && lanes[index]?.expected == commit.sha {
        lanes[index] = nil
      }

      var transitions: [PendingTransition] = lanes.indices.compactMap { index in
        guard index != column, let lane = lanes[index] else { return nil }
        return PendingTransition(fromLane: index, toLane: index, expected: lane.expected, color: lane.color, startsAtNode: false)
      }

      lanes[column] = nil
      for (position, parent) in commit.parents.enumerated() {
        if position == 0 {
          lanes[column] = Lane(expected: parent, color: nodeColor)
          transitions.append(
            PendingTransition(fromLane: column, toLane: column, expected: parent, color: nodeColor, startsAtNode: true)
          )
        } else if let existing = lanes.firstIndex(where: { $0?.expected == parent }) {
          let color = lanes[existing]?.color ?? nodeColor
          transitions.append(
            PendingTransition(fromLane: column, toLane: existing, expected: parent, color: color, startsAtNode: true)
          )
        } else {
          let color = allocateColor()
          let lane = claimLane(expected: parent, color: color)
          transitions.append(
            PendingTransition(fromLane: column, toLane: lane, expected: parent, color: color, startsAtNode: true)
          )
        }
      }
      trimTrailingLanes()

      if let next {
        let nextColumn = lanes.firstIndex { $0?.expected == next.sha } ?? (lanes.firstIndex { $0 == nil } ?? lanes.count)
        transitions = transitions.map { transition in
          guard transition.expected == next.sha else { return transition }
          var bent = transition
          bent.toLane = nextColumn
          return bent
        }
      }
      outgoing.append(transitions)
      laneCounts.append(max(laneCountBefore, lanes.count, column + 1))
    }

    mutating func finish() -> GraphLayout {
      let rows = nodeLanes.indices.map { index in
        GraphRow(
          nodeLane: nodeLanes[index],
          nodeColorIndex: nodeColors[index],
          incoming: index > 0 ? outgoing[index - 1].map(\.resolved) : [],
          outgoing: outgoing[index].map(\.resolved),
          laneCount: laneCounts[index]
        )
      }
      return GraphLayout(rows: rows, maxLaneCount: laneCounts.max() ?? 0)
    }

    private mutating func allocateColor() -> Int {
      defer { nextColor += 1 }
      return nextColor
    }

    private mutating func claimLane(expected: String, color: Int) -> Int {
      if let free = lanes.firstIndex(where: { $0 == nil }) {
        lanes[free] = Lane(expected: expected, color: color)
        return free
      }
      lanes.append(Lane(expected: expected, color: color))
      return lanes.count - 1
    }

    private mutating func trimTrailingLanes() {
      while lanes.last == nil, !lanes.isEmpty { lanes.removeLast() }
    }
  }
}
