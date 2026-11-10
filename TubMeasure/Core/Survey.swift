import Foundation

/// Who and where the job is for. Stored only on the device.
struct JobInfo: Codable, Hashable {
    var customerName = ""
    var address = ""
    var prospectNumber = ""
}

struct SurveyPhoto: Codable, Hashable, Identifiable {
    var id = UUID()
    var fileName: String
}

/// The office paperwork for one job: form answers typed in by hand, and the photo checklist.
/// Values the scan can supply are not stored here; see `SurveyResolver`.
struct Survey: Codable, Hashable {
    var info = JobInfo()
    /// Hand-entered answers by field id. A hand-entered answer overrides the scan.
    var answers: [String: String] = [:]
    var photos: [String: [SurveyPhoto]] = [:]
    var photoNotes: [String: String] = [:]
    /// Reason a photo was not taken (for example "Requested no photos").
    var photoSkips: [String: String] = [:]
}

enum FieldInput: Hashable {
    case yesNo
    case choice([String])
    case text
    case inches
    case feet
    /// Whole inches joined with "x", e.g. "109x74x98". The labels name each part.
    case dimensions([String])
}

enum FieldCondition: Hashable {
    case oneOf(String, [String])
    case noneOf(String, [String])
}

struct SurveyField: Identifiable, Hashable {
    let id: String
    let title: String
    let section: String
    let input: FieldInput
    var hint: String? = nil
    var showIf: FieldCondition? = nil
}

struct PhotoItem: Identifiable, Hashable {
    let id: String
    let title: String
    var hint: String? = nil
    var required = true
}

/// The measurement and photo forms, in the order the office forms list them.
enum SurveyForm {
    static let yes = "Yes", no = "No"
    static let otherDoorChoices = ["No", "Yes, 1 additional door", "Yes, 2 additional doors", "Yes, 3 additional doors"]

    static let fields: [SurveyField] = [
        SurveyField(id: "residence", title: "Residence", section: "Home",
                    input: .choice(["Single Family Residence", "Townhouse", "Condo", "Apartment", "Mobile Home", "Other"])),
        SurveyField(id: "mainPanelLocation", title: "Main Panel Location", section: "Electrical",
                    input: .choice(["Basement", "Garage", "Utility Room", "Closet", "Hallway", "Exterior", "Other"])),
        SurveyField(id: "subPanel", title: "Is there an Existing Sub Panel?", section: "Electrical", input: .yesNo),
        SurveyField(id: "panelDistance", title: "Distance from Main or Sub Panel to Install Location (whichever one will be used) (Feet)",
                    section: "Electrical", input: .feet),
        SurveyField(id: "exteriorEntrance", title: "Dimensions of Exterior Entrance/Exit to Home (Inches)", section: "Access",
                    input: .dimensions(["Width", "Height"])),
        SurveyField(id: "exteriorGroundLevel", title: "Is the Exterior Entrance to be used on Ground Level?", section: "Access", input: .yesNo),
        SurveyField(id: "foundation", title: "Foundation Type", section: "Home",
                    input: .choice(["Basement", "Crawl Space", "Slab", "Other"])),
        SurveyField(id: "attic", title: "Is there Attic Access?", section: "Home", input: .yesNo),
        SurveyField(id: "vaulted", title: "Does the Home have Vaulted Ceilings?", section: "Home", input: .yesNo),
        SurveyField(id: "floor", title: "On Which Floor of the Home will the Walk-In Tub be Installed?", section: "Access",
                    input: .choice(["First", "Second", "Third", "Basement"])),
        SurveyField(id: "floorAccess", title: "If Not on the First Floor, how will the Installers Access the Floor for Install? (Stairs, Elevator, Etc.)",
                    section: "Access", input: .choice(["Stairs", "Elevator", "Other"]), showIf: .noneOf("floor", ["First"])),
        SurveyField(id: "floorAccessOther", title: "Describe other way to access the Floor if not Stairs or Elevator", section: "Access",
                    input: .text, showIf: .oneOf("floorAccess", ["Other"])),
        SurveyField(id: "roomSize", title: "Overall Measurement of the Room where we are Installing the Tub (Inches L x W x H)",
                    section: "Bathroom", input: .dimensions(["Length", "Width", "Height"])),
        SurveyField(id: "hallway", title: "Is there a Hallway leading to the Install Room?", section: "Access", input: .yesNo),
        SurveyField(id: "hallwayWidth", title: "Width of Hallway Leading up to Tub Install (Inches)", section: "Access",
                    input: .inches, showIf: .oneOf("hallway", ["Yes"])),
        SurveyField(id: "doorwayWidth", title: "Width of Doorway to Room we are Installing Tub (Inches)", section: "Access", input: .inches),
        SurveyField(id: "otherDoors", title: "Are there any other Doors in the Home to be R&R'd?", section: "Access",
                    input: .choice(otherDoorChoices)),
        SurveyField(id: "otherDoor1Width", title: "Width of Additional Door #1 to be R&R'd (Inches)", section: "Access", input: .inches,
                    showIf: .oneOf("otherDoors", Array(otherDoorChoices[1...]))),
        SurveyField(id: "otherDoor2Width", title: "Width of Additional Door #2 to be R&R'd (Inches)", section: "Access", input: .inches,
                    showIf: .oneOf("otherDoors", Array(otherDoorChoices[2...]))),
        SurveyField(id: "otherDoor3Width", title: "Width of Additional Door #3 to be R&R'd (Inches)", section: "Access", input: .inches,
                    showIf: .oneOf("otherDoors", [otherDoorChoices[3]])),
        SurveyField(id: "installArea", title: "In Which Area of the Room will the New Tub be Installed", section: "Bathroom",
                    input: .choice(["Existing Tub Location", "Existing Shower Location", "Other Location"])),
        SurveyField(id: "tubArea", title: "Measurement of Existing Tub Area with Surrounding Shelving/Tile (Inches L x W x H)",
                    section: "Existing tub", input: .dimensions(["Depth", "Length", "Height"]),
                    hint: "Same order as the existing tub: depth from the wall, length along the wall, then height to the top of the tile."),
        SurveyField(id: "existingTub", title: "Measurement of Existing Tub to be Removed (Inches L x W x H)", section: "Existing tub",
                    input: .dimensions(["Depth", "Length", "Height"]),
                    hint: "Depth from the wall, length along the wall, rim height (e.g. 31x59x15)."),
        SurveyField(id: "drainSide", title: "Existing Tub Drain Location", section: "Existing tub",
                    input: .choice(["Left", "Right", "Center"]), hint: "As seen standing in front of the tub, facing it."),
        SurveyField(id: "tubMaterial", title: "Existing Tub Material to be Removed", section: "Existing tub",
                    input: .choice(["Cast Iron", "Steel", "Acrylic", "Fiberglass", "Tile / Custom", "Other"])),
        SurveyField(id: "surroundRemoved", title: "Will Existing Tub Surround be Removed?", section: "Existing tub", input: .yesNo),
        SurveyField(id: "toilet", title: "Is there an Existing Toilet?", section: "Toilet", input: .yesNo),
        SurveyField(id: "toiletToTub", title: "Distance from Center of Toilet Drain to Outside Edge of Existing Tub/Shower (Inches)",
                    section: "Toilet", input: .inches, showIf: .oneOf("toilet", ["Yes"])),
        SurveyField(id: "shelfAboveToilet", title: "Is there Shelving or Counter above the Toilet?", section: "Toilet", input: .yesNo,
                    showIf: .oneOf("toilet", ["Yes"])),
        SurveyField(id: "shelfHeight", title: "Height (inches) from Floor to Bottom of Shelf or Counter (Minimum 34\")", section: "Toilet",
                    input: .inches, showIf: .oneOf("shelfAboveToilet", ["Yes"])),
        SurveyField(id: "waterHeater", title: "Water Heater Type", section: "Home",
                    input: .choice(["Tank", "Tankless", "Boiler / Indirect", "Other"])),
        SurveyField(id: "gateCode", title: "Gate Code", section: "Home", input: .text),
    ]

    static let photos: [PhotoItem] = [
        PhotoItem(id: "customers", title: "Customer(s) who will use the tub",
                  hint: "Required. If they decline, mark it skipped with \"Requested no photos\"."),
        PhotoItem(id: "room", title: "The room (bathroom) where the tub is going"),
        PhotoItem(id: "tubEntire", title: "Existing tub, 1 of 2: entire tub"),
        PhotoItem(id: "tubDrain", title: "Existing tub, 2 of 2: drain location",
                  hint: "After marking the drain in the scan, a snapshot from the scan screen is stamped with the drain measurements."),
        PhotoItem(id: "window", title: "Existing window"),
        PhotoItem(id: "toiletToTub", title: "Distance from centre of toilet (or drain) to nearest edge of bath/shower",
                  hint: "A snapshot from the scan screen is stamped with this distance once the flange bolts are marked."),
        PhotoItem(id: "roughIn", title: "Toilet rough-in: drywall to centre of bolt",
                  hint: "A snapshot from the scan screen is stamped with the rough-in once the bolts are marked."),
        PhotoItem(id: "doorInterior", title: "Doorway to the room, from the interior side"),
        PhotoItem(id: "doorExterior", title: "Doorway to the room, from the exterior side"),
        PhotoItem(id: "mainPanel", title: "Main panel", hint: "Check that the picture is clear."),
        PhotoItem(id: "breakers", title: "Breakers", hint: "The amps on the breakers must be readable."),
        PhotoItem(id: "panelLabel", title: "Main panel label", hint: "Check that the picture is clear."),
        PhotoItem(id: "exterior", title: "Outside entrance and front of home (if different)"),
        PhotoItem(id: "waterHeater", title: "Water heater, full view"),
        PhotoItem(id: "waterHeaterLabel", title: "Water heater label"),
        PhotoItem(id: "waterHeaterCloset", title: "Water heater cabinet or closet"),
        PhotoItem(id: "ponyWalls", title: "Pony wall(s) or return walls"),
        PhotoItem(id: "vanity", title: "Existing vanity (if not already in other pictures)"),
        PhotoItem(id: "other", title: "Other: anything else the installers should know", required: false),
    ]

    static func field(_ id: String) -> SurveyField? { fields.first { $0.id == id } }
}
