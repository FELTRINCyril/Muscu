import Foundation

/// Groupe de mouvement : les exercices d'un meme groupe sont interchangeables
/// (utilise par le generateur pour la selection et par le swap d'alternatives).
public enum MovementGroup: String, CaseIterable, Sendable {
    case chestPressHorizontal, chestPressIncline, chestPressDecline, chestFly, chestDip, pushup
    case verticalPull, horizontalPull, pullover, deadlift, backExtension
    case shoulderPress, lateralRaise, frontRaise, rearDelt, facePull, shrug
    case bicepsCurl, hammerCurl, preacherCurl, tricepsExtension, tricepsDip, skullcrusher, kickback
    case squat, legPress, lunge, hipHinge, hipThrust, legExtension, legCurl
    case calfStanding, calfSeated, calfPress
    case crunch, legRaise, plank, rotation
}

/// Un exercice "classique de salle" : reference vers le catalogue + groupe + rang
/// de preference dans le groupe (1 = le plus classique).
public struct StapleExercise: Sendable {
    public let catalogId: String
    public let group: MovementGroup
    public let rank: Int
}

/// Liste blanche curee des exercices classiques. Le generateur et les templates
/// ne piochent QUE dans cette liste (repli catalogue complet si aucun candidat).
/// Chaque id est verifie par StapleExercisesTests contre exercises_fr.json.
public enum StapleExercises {
    public static let all: [StapleExercise] = [
        // Pecs - presses horizontales
        .init(catalogId: "Barbell_Bench_Press_-_Medium_Grip", group: .chestPressHorizontal, rank: 1),
        .init(catalogId: "Dumbbell_Bench_Press", group: .chestPressHorizontal, rank: 2),
        .init(catalogId: "Machine_Bench_Press", group: .chestPressHorizontal, rank: 3),
        .init(catalogId: "Smith_Machine_Bench_Press", group: .chestPressHorizontal, rank: 4),
        .init(catalogId: "Leverage_Chest_Press", group: .chestPressHorizontal, rank: 5),
        .init(catalogId: "Cable_Chest_Press", group: .chestPressHorizontal, rank: 6),
        // Pecs - presses inclinees
        .init(catalogId: "Barbell_Incline_Bench_Press_-_Medium_Grip", group: .chestPressIncline, rank: 1),
        .init(catalogId: "Incline_Dumbbell_Press", group: .chestPressIncline, rank: 2),
        .init(catalogId: "Smith_Machine_Incline_Bench_Press", group: .chestPressIncline, rank: 3),
        .init(catalogId: "Leverage_Incline_Chest_Press", group: .chestPressIncline, rank: 4),
        // Pecs - presses declinees
        .init(catalogId: "Decline_Barbell_Bench_Press", group: .chestPressDecline, rank: 1),
        .init(catalogId: "Decline_Dumbbell_Bench_Press", group: .chestPressDecline, rank: 2),
        .init(catalogId: "Smith_Machine_Decline_Press", group: .chestPressDecline, rank: 3),
        .init(catalogId: "Leverage_Decline_Chest_Press", group: .chestPressDecline, rank: 4),
        // Pecs - ecartes
        .init(catalogId: "Dumbbell_Flyes", group: .chestFly, rank: 1),
        .init(catalogId: "Butterfly", group: .chestFly, rank: 2),
        .init(catalogId: "Cable_Crossover", group: .chestFly, rank: 3),
        .init(catalogId: "Low_Cable_Crossover", group: .chestFly, rank: 4),
        .init(catalogId: "Incline_Dumbbell_Flyes", group: .chestFly, rank: 5),
        .init(catalogId: "Flat_Bench_Cable_Flyes", group: .chestFly, rank: 6),
        // Pecs - dips et pompes
        .init(catalogId: "Dips_-_Chest_Version", group: .chestDip, rank: 1),
        .init(catalogId: "Pushups", group: .pushup, rank: 1),
        .init(catalogId: "Push-Up_Wide", group: .pushup, rank: 2),
        .init(catalogId: "Incline_Push-Up", group: .pushup, rank: 3),
        .init(catalogId: "Decline_Push-Up", group: .pushup, rank: 4),
        // Dos - tirages verticaux
        .init(catalogId: "Pullups", group: .verticalPull, rank: 1),
        .init(catalogId: "Wide-Grip_Lat_Pulldown", group: .verticalPull, rank: 2),
        .init(catalogId: "Chin-Up", group: .verticalPull, rank: 3),
        .init(catalogId: "One_Arm_Lat_Pulldown", group: .verticalPull, rank: 4),
        .init(catalogId: "Close-Grip_Front_Lat_Pulldown", group: .verticalPull, rank: 5),
        .init(catalogId: "V-Bar_Pulldown", group: .verticalPull, rank: 6),
        .init(catalogId: "Underhand_Cable_Pulldowns", group: .verticalPull, rank: 7),
        // Dos - tirages horizontaux
        .init(catalogId: "Bent_Over_Barbell_Row", group: .horizontalPull, rank: 1),
        .init(catalogId: "One-Arm_Dumbbell_Row", group: .horizontalPull, rank: 2),
        .init(catalogId: "Seated_Cable_Rows", group: .horizontalPull, rank: 3),
        .init(catalogId: "T-Bar_Row_with_Handle", group: .horizontalPull, rank: 4),
        .init(catalogId: "Lying_T-Bar_Row", group: .horizontalPull, rank: 5),
        .init(catalogId: "Leverage_Iso_Row", group: .horizontalPull, rank: 6),
        .init(catalogId: "Smith_Machine_Bent_Over_Row", group: .horizontalPull, rank: 7),
        .init(catalogId: "Inverted_Row", group: .horizontalPull, rank: 8),
        // Dos - pullovers
        .init(catalogId: "Straight-Arm_Dumbbell_Pullover", group: .pullover, rank: 1),
        .init(catalogId: "Bent-Arm_Dumbbell_Pullover", group: .pullover, rank: 2),
        .init(catalogId: "Bent-Arm_Barbell_Pullover", group: .pullover, rank: 3),
        .init(catalogId: "Straight-Arm_Pulldown", group: .pullover, rank: 4),
        // Dos - souleve de terre et lombaires
        .init(catalogId: "Barbell_Deadlift", group: .deadlift, rank: 1),
        .init(catalogId: "Sumo_Deadlift", group: .deadlift, rank: 2),
        .init(catalogId: "Trap_Bar_Deadlift", group: .deadlift, rank: 3),
        .init(catalogId: "Hyperextensions_Back_Extensions", group: .backExtension, rank: 1),
        .init(catalogId: "Hyperextensions_With_No_Hyperextension_Bench", group: .backExtension, rank: 2),
        // Epaules - developpes
        .init(catalogId: "Standing_Military_Press", group: .shoulderPress, rank: 1),
        .init(catalogId: "Dumbbell_Shoulder_Press", group: .shoulderPress, rank: 2),
        .init(catalogId: "Seated_Barbell_Military_Press", group: .shoulderPress, rank: 3),
        .init(catalogId: "Arnold_Dumbbell_Press", group: .shoulderPress, rank: 4),
        .init(catalogId: "Machine_Shoulder_Military_Press", group: .shoulderPress, rank: 5),
        .init(catalogId: "Smith_Machine_Overhead_Shoulder_Press", group: .shoulderPress, rank: 6),
        .init(catalogId: "Leverage_Shoulder_Press", group: .shoulderPress, rank: 7),
        // Epaules - elevations et arriere
        .init(catalogId: "Side_Lateral_Raise", group: .lateralRaise, rank: 1),
        .init(catalogId: "Seated_Side_Lateral_Raise", group: .lateralRaise, rank: 2),
        .init(catalogId: "Cable_Seated_Lateral_Raise", group: .lateralRaise, rank: 3),
        .init(catalogId: "Front_Dumbbell_Raise", group: .frontRaise, rank: 1),
        .init(catalogId: "Front_Two-Dumbbell_Raise", group: .frontRaise, rank: 2),
        .init(catalogId: "Front_Cable_Raise", group: .frontRaise, rank: 3),
        .init(catalogId: "Front_Plate_Raise", group: .frontRaise, rank: 4),
        .init(catalogId: "Reverse_Flyes", group: .rearDelt, rank: 1),
        .init(catalogId: "Reverse_Machine_Flyes", group: .rearDelt, rank: 2),
        .init(catalogId: "Cable_Rear_Delt_Fly", group: .rearDelt, rank: 3),
        .init(catalogId: "Seated_Bent-Over_Rear_Delt_Raise", group: .rearDelt, rank: 4),
        .init(catalogId: "Face_Pull", group: .facePull, rank: 1),
        // Epaules - shrugs
        .init(catalogId: "Barbell_Shrug", group: .shrug, rank: 1),
        .init(catalogId: "Dumbbell_Shrug", group: .shrug, rank: 2),
        .init(catalogId: "Cable_Shrugs", group: .shrug, rank: 3),
        .init(catalogId: "Leverage_Shrug", group: .shrug, rank: 4),
        // Biceps
        .init(catalogId: "Barbell_Curl", group: .bicepsCurl, rank: 1),
        .init(catalogId: "EZ-Bar_Curl", group: .bicepsCurl, rank: 2),
        .init(catalogId: "Dumbbell_Alternate_Bicep_Curl", group: .bicepsCurl, rank: 3),
        .init(catalogId: "Dumbbell_Bicep_Curl", group: .bicepsCurl, rank: 4),
        .init(catalogId: "Standing_Biceps_Cable_Curl", group: .bicepsCurl, rank: 5),
        .init(catalogId: "Machine_Bicep_Curl", group: .bicepsCurl, rank: 6),
        .init(catalogId: "Concentration_Curls", group: .bicepsCurl, rank: 7),
        .init(catalogId: "Incline_Dumbbell_Curl", group: .bicepsCurl, rank: 8),
        .init(catalogId: "Hammer_Curls", group: .hammerCurl, rank: 1),
        .init(catalogId: "Cable_Hammer_Curls_-_Rope_Attachment", group: .hammerCurl, rank: 2),
        .init(catalogId: "Alternate_Hammer_Curl", group: .hammerCurl, rank: 3),
        .init(catalogId: "Preacher_Curl", group: .preacherCurl, rank: 1),
        .init(catalogId: "Machine_Preacher_Curls", group: .preacherCurl, rank: 2),
        .init(catalogId: "Two-Arm_Dumbbell_Preacher_Curl", group: .preacherCurl, rank: 3),
        .init(catalogId: "Cable_Preacher_Curl", group: .preacherCurl, rank: 4),
        // Triceps
        .init(catalogId: "Triceps_Pushdown", group: .tricepsExtension, rank: 1),
        .init(catalogId: "Triceps_Pushdown_-_Rope_Attachment", group: .tricepsExtension, rank: 2),
        .init(catalogId: "Triceps_Pushdown_-_V-Bar_Attachment", group: .tricepsExtension, rank: 3),
        .init(catalogId: "Cable_Rope_Overhead_Triceps_Extension", group: .tricepsExtension, rank: 4),
        .init(catalogId: "Standing_Dumbbell_Triceps_Extension", group: .tricepsExtension, rank: 5),
        .init(catalogId: "Machine_Triceps_Extension", group: .tricepsExtension, rank: 6),
        .init(catalogId: "Dips_-_Triceps_Version", group: .tricepsDip, rank: 1),
        .init(catalogId: "Bench_Dips", group: .tricepsDip, rank: 2),
        .init(catalogId: "Dip_Machine", group: .tricepsDip, rank: 3),
        .init(catalogId: "Parallel_Bar_Dip", group: .tricepsDip, rank: 4),
        .init(catalogId: "Lying_Triceps_Press", group: .skullcrusher, rank: 1),
        .init(catalogId: "EZ-Bar_Skullcrusher", group: .skullcrusher, rank: 2),
        .init(catalogId: "Tricep_Dumbbell_Kickback", group: .kickback, rank: 1),
        // Jambes - squats et presses
        .init(catalogId: "Barbell_Squat", group: .squat, rank: 1),
        .init(catalogId: "Barbell_Full_Squat", group: .squat, rank: 2),
        .init(catalogId: "Smith_Machine_Squat", group: .squat, rank: 3),
        .init(catalogId: "Front_Barbell_Squat", group: .squat, rank: 4),
        .init(catalogId: "Goblet_Squat", group: .squat, rank: 5),
        .init(catalogId: "Dumbbell_Squat", group: .squat, rank: 6),
        .init(catalogId: "Bodyweight_Squat", group: .squat, rank: 7),
        .init(catalogId: "Leg_Press", group: .legPress, rank: 1),
        .init(catalogId: "Hack_Squat", group: .legPress, rank: 2),
        // Jambes - fentes
        .init(catalogId: "Dumbbell_Lunges", group: .lunge, rank: 1),
        .init(catalogId: "Barbell_Lunge", group: .lunge, rank: 2),
        .init(catalogId: "Barbell_Walking_Lunge", group: .lunge, rank: 3),
        .init(catalogId: "Bodyweight_Walking_Lunge", group: .lunge, rank: 4),
        .init(catalogId: "Split_Squat_with_Dumbbells", group: .lunge, rank: 5),
        .init(catalogId: "Dumbbell_Rear_Lunge", group: .lunge, rank: 6),
        // Jambes - hinge et ischio
        .init(catalogId: "Romanian_Deadlift", group: .hipHinge, rank: 1),
        .init(catalogId: "Stiff-Legged_Barbell_Deadlift", group: .hipHinge, rank: 2),
        .init(catalogId: "Stiff-Legged_Dumbbell_Deadlift", group: .hipHinge, rank: 3),
        .init(catalogId: "Good_Morning", group: .hipHinge, rank: 4),
        .init(catalogId: "Barbell_Hip_Thrust", group: .hipThrust, rank: 1),
        .init(catalogId: "Barbell_Glute_Bridge", group: .hipThrust, rank: 2),
        .init(catalogId: "Leg_Extensions", group: .legExtension, rank: 1),
        .init(catalogId: "Lying_Leg_Curls", group: .legCurl, rank: 1),
        .init(catalogId: "Seated_Leg_Curl", group: .legCurl, rank: 2),
        .init(catalogId: "Standing_Leg_Curl", group: .legCurl, rank: 3),
        // Mollets
        .init(catalogId: "Standing_Calf_Raises", group: .calfStanding, rank: 1),
        .init(catalogId: "Standing_Barbell_Calf_Raise", group: .calfStanding, rank: 2),
        .init(catalogId: "Standing_Dumbbell_Calf_Raise", group: .calfStanding, rank: 3),
        .init(catalogId: "Smith_Machine_Calf_Raise", group: .calfStanding, rank: 4),
        .init(catalogId: "Seated_Calf_Raise", group: .calfSeated, rank: 1),
        .init(catalogId: "Barbell_Seated_Calf_Raise", group: .calfSeated, rank: 2),
        .init(catalogId: "Calf_Press_On_The_Leg_Press_Machine", group: .calfPress, rank: 1),
        .init(catalogId: "Calf_Press", group: .calfPress, rank: 2),
        // Abdos
        .init(catalogId: "Crunches", group: .crunch, rank: 1),
        .init(catalogId: "Cable_Crunch", group: .crunch, rank: 2),
        .init(catalogId: "Ab_Crunch_Machine", group: .crunch, rank: 3),
        .init(catalogId: "Decline_Crunch", group: .crunch, rank: 4),
        .init(catalogId: "Exercise_Ball_Crunch", group: .crunch, rank: 5),
        .init(catalogId: "Oblique_Crunches", group: .crunch, rank: 6),
        .init(catalogId: "Hanging_Leg_Raise", group: .legRaise, rank: 1),
        .init(catalogId: "Flat_Bench_Lying_Leg_Raise", group: .legRaise, rank: 2),
        .init(catalogId: "Leg_Pull-In", group: .legRaise, rank: 3),
        .init(catalogId: "Plank", group: .plank, rank: 1),
        .init(catalogId: "Side_Bridge", group: .plank, rank: 2),
        .init(catalogId: "Ab_Roller", group: .plank, rank: 3),
        .init(catalogId: "Russian_Twist", group: .rotation, rank: 1),
        .init(catalogId: "Cable_Russian_Twists", group: .rotation, rank: 2),
    ]

    private static let byId: [String: StapleExercise] = Dictionary(
        uniqueKeysWithValues: all.map { ($0.catalogId, $0) }
    )

    public static func staple(for catalogId: String) -> StapleExercise? {
        byId[catalogId]
    }

    public static func members(of group: MovementGroup) -> [StapleExercise] {
        all.filter { $0.group == group }.sorted { $0.rank < $1.rank }
    }
}
