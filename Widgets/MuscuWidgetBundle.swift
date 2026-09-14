import WidgetKit
import SwiftUI

@main
struct MuscuWidgetBundle: WidgetBundle {
    var body: some Widget {
        NextSessionWidget()
        WeeklyVolumeWidget()
        WorkoutLiveActivity()
    }
}
