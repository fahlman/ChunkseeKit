import Foundation
@testable import ChunkseeKit

enum PortalFixtures {
    static func definition(scale: Double) -> NBT {
        .compound(["min_y": .int(0), "height": .int(256), "logical_height": .int(256),
                   "has_ceiling": .byte(0), "coordinate_scale": .double(scale)])
    }

    static var types: [String: DimensionType] {
        [NetherPortal.overworld: DimensionType(definition(scale: 1))!,
         NetherPortal.nether: DimensionType(definition(scale: 8))!]
    }

    static var border: WorldBorder {
        WorldBorder(centerX: 0, centerZ: 0, size: 59_999_968, targetSize: 59_999_968, lerpTime: 0,
                    damagePerBlock: 0.2, safeZone: 5, warningBlocks: 5, warningTime: 15)
    }

    static var borders: [String: WorldBorder] {
        [NetherPortal.overworld: border, NetherPortal.nether: border]
    }
}
