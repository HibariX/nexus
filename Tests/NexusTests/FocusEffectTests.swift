import Foundation
import Testing
@testable import Nexus

@Suite struct FocusEffectTests {
    @Test("每种特效都有展示名") func everyEffectHasDisplayName() {
        #expect(FocusEffect.allCases.count == 3)
        for effect in FocusEffect.allCases {
            #expect(!effect.displayName.isEmpty)
        }
    }

    @Test("默认特效为扫描线") func defaultIsScanline() {
        #expect(AppSettings.defaultFocusEffect == .scanline)
    }

    @Test("枚举可编解码往返") func codableRoundTrip() throws {
        for effect in FocusEffect.allCases {
            let data = try JSONEncoder().encode(effect)
            let decoded = try JSONDecoder().decode(FocusEffect.self, from: data)
            #expect(decoded == effect)
        }
    }
}
