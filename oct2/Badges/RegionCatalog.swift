import Foundation
import SwiftUI

nonisolated struct RegionDef: Identifiable, Hashable, Sendable {
    let id: String          // "US-CA"
    let code: String        // "CA"
    let name: String        // "California"
    let aliases: [String]
    let tile: TilePos?
}

nonisolated struct TilePos: Hashable, Sendable {
    let col: Int
    let row: Int
}

nonisolated struct CountryAtlas: Identifiable, Hashable, Sendable {
    let code: String
    let unitName: String      // "States"
    let regions: [RegionDef]
    let colors: [UInt32]
    var id: String { code }

    var title: String { Flag.name(code) }
    var tileColumns: Int { (regions.compactMap { $0.tile?.col }.max() ?? -1) + 1 }
    var tileRows: Int { (regions.compactMap { $0.tile?.row }.max() ?? -1) + 1 }
    var hasTileMap: Bool { regions.allSatisfy { $0.tile != nil } }
    var swiftColors: [Color] { colors.map { Color(hex: $0) } }
}

/// Region data for the detailed badge maps, plus address matching.
nonisolated enum RegionCatalog {
    static let atlases: [CountryAtlas] = [unitedStates, japan, korea, taiwan, canada, france, unitedKingdom, morocco]

    private static let byCountry: [String: CountryAtlas] = Dictionary(uniqueKeysWithValues: atlases.map { ($0.code, $0) })
    private static let byRegionID: [String: RegionDef] = Dictionary(uniqueKeysWithValues: atlases.flatMap(\.regions).map { ($0.id, $0) })
    private static let aliasIndex: [String: [String: RegionDef]] = {
        var out: [String: [String: RegionDef]] = [:]
        for atlas in atlases {
            var map: [String: RegionDef] = [:]
            for r in atlas.regions {
                for alias in [r.name, r.code] + r.aliases {
                    let key = normalize(alias)
                    if !key.isEmpty, map[key] == nil { map[key] = r }
                }
            }
            out[atlas.code] = map
        }
        return out
    }()

    static func atlas(for countryCode: String?) -> CountryAtlas? {
        guard let countryCode else { return nil }
        return byCountry[countryCode.uppercased()]
    }

    static func region(id: String?) -> RegionDef? {
        guard let id else { return nil }
        return byRegionID[id]
    }

    static func normalize(_ s: String) -> String {
        let folded = s.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US"))
        return String(folded.lowercased().unicodeScalars.filter { CharacterSet.letters.contains($0) }.map(Character.init))
    }

    /// Finds the region for an address. Address parts run small → large, so we scan from the end.
    static func match(countryCode: String?, addressLines: [String]) -> RegionDef? {
        guard let cc = countryCode?.uppercased(), let index = aliasIndex[cc] else { return nil }

        if cc == "FR", let r = franceByPostcode(addressLines) { return r }

        let components = addressLines
            .flatMap { $0.components(separatedBy: CharacterSet(charactersIn: ",\n")) }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        for component in components.reversed() {
            let words = component.split(whereSeparator: { $0 == " " }).map(String.init)
            guard !words.isEmpty else { continue }
            for n in stride(from: min(words.count, 5), through: 1, by: -1) {
                for start in 0...(words.count - n) {
                    let key = normalize(words[start..<(start + n)].joined(separator: " "))
                    if key.count >= 2, let r = index[key] { return r }
                }
            }
        }
        return nil
    }

    private static func franceByPostcode(_ lines: [String]) -> RegionDef? {
        let joined = lines.joined(separator: " ")
        guard let range = joined.range(of: #"\b\d{5}\b"#, options: .regularExpression) else { return nil }
        let dept = String(joined[range].prefix(2))
        guard let code = frenchDepartments[dept] else { return nil }
        return byRegionID["FR-\(code)"]
    }

    // MARK: - Builders

    private static func r(_ cc: String, _ code: String, _ name: String, _ aliases: [String] = [], _ col: Int? = nil, _ row: Int? = nil) -> RegionDef {
        RegionDef(
            id: "\(cc)-\(code)",
            code: code,
            name: name,
            aliases: aliases,
            tile: col.flatMap { c in row.map { TilePos(col: c, row: $0) } }
        )
    }

    // MARK: - United States (tile cartogram)

    static let unitedStates = CountryAtlas(code: "US", unitName: "States", regions: [
        r("US", "AK", "Alaska", [], 0, 0), r("US", "ME", "Maine", [], 10, 0),
        r("US", "VT", "Vermont", [], 9, 1), r("US", "NH", "New Hampshire", [], 10, 1),
        r("US", "WA", "Washington", [], 0, 2), r("US", "ID", "Idaho", [], 1, 2), r("US", "MT", "Montana", [], 2, 2),
        r("US", "ND", "North Dakota", [], 3, 2), r("US", "MN", "Minnesota", [], 4, 2), r("US", "IL", "Illinois", [], 5, 2),
        r("US", "WI", "Wisconsin", [], 6, 2), r("US", "MI", "Michigan", [], 7, 2), r("US", "NY", "New York", [], 8, 2),
        r("US", "RI", "Rhode Island", [], 9, 2), r("US", "MA", "Massachusetts", [], 10, 2),
        r("US", "OR", "Oregon", [], 0, 3), r("US", "NV", "Nevada", [], 1, 3), r("US", "WY", "Wyoming", [], 2, 3),
        r("US", "SD", "South Dakota", [], 3, 3), r("US", "IA", "Iowa", [], 4, 3), r("US", "IN", "Indiana", [], 5, 3),
        r("US", "OH", "Ohio", [], 6, 3), r("US", "PA", "Pennsylvania", [], 7, 3), r("US", "NJ", "New Jersey", [], 8, 3),
        r("US", "CT", "Connecticut", [], 9, 3),
        r("US", "CA", "California", [], 0, 4), r("US", "UT", "Utah", [], 1, 4), r("US", "CO", "Colorado", [], 2, 4),
        r("US", "NE", "Nebraska", [], 3, 4), r("US", "MO", "Missouri", [], 4, 4), r("US", "KY", "Kentucky", [], 5, 4),
        r("US", "WV", "West Virginia", [], 6, 4), r("US", "VA", "Virginia", [], 7, 4), r("US", "MD", "Maryland", [], 8, 4),
        r("US", "DE", "Delaware", [], 9, 4),
        r("US", "AZ", "Arizona", [], 1, 5), r("US", "NM", "New Mexico", [], 2, 5), r("US", "KS", "Kansas", [], 3, 5),
        r("US", "AR", "Arkansas", [], 4, 5), r("US", "TN", "Tennessee", [], 5, 5), r("US", "NC", "North Carolina", [], 6, 5),
        r("US", "SC", "South Carolina", [], 7, 5), r("US", "DC", "District of Columbia", ["Washington DC", "Washington D.C."], 8, 5),
        r("US", "OK", "Oklahoma", [], 3, 6), r("US", "LA", "Louisiana", [], 4, 6), r("US", "MS", "Mississippi", [], 5, 6),
        r("US", "AL", "Alabama", [], 6, 6), r("US", "GA", "Georgia", [], 7, 6),
        r("US", "HI", "Hawaii", [], 0, 7), r("US", "TX", "Texas", [], 3, 7), r("US", "FL", "Florida", [], 8, 7)
    ], colors: [0x2F7CF6, 0x7C5CFA, 0xF43F72])

    // MARK: - Japan

    private static func jp(_ code: String, _ name: String, _ kanji: String) -> RegionDef {
        r("JP", code, name, [kanji, "\(name) Prefecture", "\(name)-ken", "\(name)-fu", "\(name)-to"])
    }

    static let japan = CountryAtlas(code: "JP", unitName: "Prefectures", regions: [
        jp("01", "Hokkaido", "北海道"), jp("02", "Aomori", "青森県"), jp("03", "Iwate", "岩手県"), jp("04", "Miyagi", "宮城県"),
        jp("05", "Akita", "秋田県"), jp("06", "Yamagata", "山形県"), jp("07", "Fukushima", "福島県"), jp("08", "Ibaraki", "茨城県"),
        jp("09", "Tochigi", "栃木県"), jp("10", "Gunma", "群馬県"), jp("11", "Saitama", "埼玉県"), jp("12", "Chiba", "千葉県"),
        jp("13", "Tokyo", "東京都"), jp("14", "Kanagawa", "神奈川県"), jp("15", "Niigata", "新潟県"), jp("16", "Toyama", "富山県"),
        jp("17", "Ishikawa", "石川県"), jp("18", "Fukui", "福井県"), jp("19", "Yamanashi", "山梨県"), jp("20", "Nagano", "長野県"),
        jp("21", "Gifu", "岐阜県"), jp("22", "Shizuoka", "静岡県"), jp("23", "Aichi", "愛知県"), jp("24", "Mie", "三重県"),
        jp("25", "Shiga", "滋賀県"), jp("26", "Kyoto", "京都府"), jp("27", "Osaka", "大阪府"), jp("28", "Hyogo", "兵庫県"),
        jp("29", "Nara", "奈良県"), jp("30", "Wakayama", "和歌山県"), jp("31", "Tottori", "鳥取県"), jp("32", "Shimane", "島根県"),
        jp("33", "Okayama", "岡山県"), jp("34", "Hiroshima", "広島県"), jp("35", "Yamaguchi", "山口県"), jp("36", "Tokushima", "徳島県"),
        jp("37", "Kagawa", "香川県"), jp("38", "Ehime", "愛媛県"), jp("39", "Kochi", "高知県"), jp("40", "Fukuoka", "福岡県"),
        jp("41", "Saga", "佐賀県"), jp("42", "Nagasaki", "長崎県"), jp("43", "Kumamoto", "熊本県"), jp("44", "Oita", "大分県"),
        jp("45", "Miyazaki", "宮崎県"), jp("46", "Kagoshima", "鹿児島県"), jp("47", "Okinawa", "沖縄県")
    ], colors: [0xF43F72, 0xFF5A36, 0xFFAE34])

    // MARK: - South Korea

    static let korea = CountryAtlas(code: "KR", unitName: "Provinces", regions: [
        r("KR", "11", "Seoul", ["서울특별시", "Seoul Special City", "서울"]),
        r("KR", "26", "Busan", ["부산광역시", "Busan Metropolitan City"]),
        r("KR", "27", "Daegu", ["대구광역시", "Daegu Metropolitan City"]),
        r("KR", "28", "Incheon", ["인천광역시", "Incheon Metropolitan City"]),
        r("KR", "29", "Gwangju", ["광주광역시", "Gwangju Metropolitan City"]),
        r("KR", "30", "Daejeon", ["대전광역시", "Daejeon Metropolitan City"]),
        r("KR", "31", "Ulsan", ["울산광역시", "Ulsan Metropolitan City"]),
        r("KR", "50", "Sejong", ["세종특별자치시", "Sejong City", "Sejong Special Self-Governing City"]),
        r("KR", "41", "Gyeonggi", ["경기도", "Gyeonggi-do", "Gyeonggi Province"]),
        r("KR", "42", "Gangwon", ["강원도", "강원특별자치도", "Gangwon-do", "Gangwon State", "Gangwon Province"]),
        r("KR", "43", "North Chungcheong", ["충청북도", "Chungcheongbuk-do", "Chungbuk"]),
        r("KR", "44", "South Chungcheong", ["충청남도", "Chungcheongnam-do", "Chungnam"]),
        r("KR", "45", "North Jeolla", ["전라북도", "전북특별자치도", "Jeollabuk-do", "Jeonbuk", "Jeonbuk State"]),
        r("KR", "46", "South Jeolla", ["전라남도", "Jeollanam-do", "Jeonnam"]),
        r("KR", "47", "North Gyeongsang", ["경상북도", "Gyeongsangbuk-do", "Gyeongbuk"]),
        r("KR", "48", "South Gyeongsang", ["경상남도", "Gyeongsangnam-do", "Gyeongnam"]),
        r("KR", "49", "Jeju", ["제주특별자치도", "Jeju-do", "Jeju Province", "Jeju Special Self-Governing Province"])
    ], colors: [0x10B5A4, 0x2F7CF6, 0xF43F72])

    // MARK: - Taiwan

    static let taiwan = CountryAtlas(code: "TW", unitName: "Counties & Cities", regions: [
        r("TW", "TPE", "Taipei City", ["臺北市", "台北市", "Taipei"]),
        r("TW", "NWT", "New Taipei City", ["新北市", "New Taipei"]),
        r("TW", "KEE", "Keelung City", ["基隆市", "Keelung"]),
        r("TW", "TAO", "Taoyuan City", ["桃園市", "Taoyuan"]),
        r("TW", "HSZ", "Hsinchu City", ["新竹市"]),
        r("TW", "HSQ", "Hsinchu County", ["新竹縣"]),
        r("TW", "MIA", "Miaoli County", ["苗栗縣", "Miaoli"]),
        r("TW", "TXG", "Taichung City", ["臺中市", "台中市", "Taichung"]),
        r("TW", "CHA", "Changhua County", ["彰化縣", "Changhua"]),
        r("TW", "NAN", "Nantou County", ["南投縣", "Nantou"]),
        r("TW", "YUN", "Yunlin County", ["雲林縣", "Yunlin"]),
        r("TW", "CYI", "Chiayi City", ["嘉義市"]),
        r("TW", "CYQ", "Chiayi County", ["嘉義縣"]),
        r("TW", "TNN", "Tainan City", ["臺南市", "台南市", "Tainan"]),
        r("TW", "KHH", "Kaohsiung City", ["高雄市", "Kaohsiung"]),
        r("TW", "PIF", "Pingtung County", ["屏東縣", "Pingtung"]),
        r("TW", "ILA", "Yilan County", ["宜蘭縣", "Yilan"]),
        r("TW", "HUA", "Hualien County", ["花蓮縣", "Hualien"]),
        r("TW", "TTT", "Taitung County", ["臺東縣", "台東縣", "Taitung"]),
        r("TW", "PEN", "Penghu County", ["澎湖縣", "Penghu"]),
        r("TW", "KIN", "Kinmen County", ["金門縣", "Kinmen"]),
        r("TW", "LIE", "Lienchiang County", ["連江縣", "Matsu", "Lienchiang"])
    ], colors: [0x7C5CFA, 0x2F7CF6, 0x10B5A4])

    // MARK: - Canada

    static let canada = CountryAtlas(code: "CA", unitName: "Provinces & Territories", regions: [
        r("CA", "BC", "British Columbia"), r("CA", "AB", "Alberta"), r("CA", "SK", "Saskatchewan"),
        r("CA", "MB", "Manitoba"), r("CA", "ON", "Ontario"), r("CA", "QC", "Quebec", ["Québec"]),
        r("CA", "NB", "New Brunswick"), r("CA", "NS", "Nova Scotia"), r("CA", "PE", "Prince Edward Island"),
        r("CA", "NL", "Newfoundland and Labrador", ["Newfoundland"]), r("CA", "YT", "Yukon"),
        r("CA", "NT", "Northwest Territories"), r("CA", "NU", "Nunavut")
    ], colors: [0xF43F72, 0xFF5A36, 0xF43F72])

    // MARK: - France (matched by postcode)

    static let france = CountryAtlas(code: "FR", unitName: "Regions", regions: [
        r("FR", "ARA", "Auvergne-Rhône-Alpes"), r("FR", "BFC", "Bourgogne-Franche-Comté"),
        r("FR", "BRE", "Brittany", ["Bretagne"]), r("FR", "CVL", "Centre-Val de Loire"),
        r("FR", "COR", "Corsica", ["Corse"]), r("FR", "GES", "Grand Est"),
        r("FR", "HDF", "Hauts-de-France"), r("FR", "IDF", "Île-de-France"),
        r("FR", "NOR", "Normandy", ["Normandie"]), r("FR", "NAQ", "Nouvelle-Aquitaine"),
        r("FR", "OCC", "Occitanie", ["Occitania"]), r("FR", "PDL", "Pays de la Loire"),
        r("FR", "PAC", "Provence-Alpes-Côte d'Azur", ["PACA", "Provence"])
    ], colors: [0x2F7CF6, 0x7C5CFA, 0xF43F72])

    private static let frenchDepartments: [String: String] = {
        let table: [String: [String]] = [
            "ARA": ["01", "03", "07", "15", "26", "38", "42", "43", "63", "69", "73", "74"],
            "BFC": ["21", "25", "39", "58", "70", "71", "89", "90"],
            "BRE": ["22", "29", "35", "56"],
            "CVL": ["18", "28", "36", "37", "41", "45"],
            "COR": ["20"],
            "GES": ["08", "10", "51", "52", "54", "55", "57", "67", "68", "88"],
            "HDF": ["02", "59", "60", "62", "80"],
            "IDF": ["75", "77", "78", "91", "92", "93", "94", "95"],
            "NOR": ["14", "27", "50", "61", "76"],
            "NAQ": ["16", "17", "19", "23", "24", "33", "40", "47", "64", "79", "86", "87"],
            "OCC": ["09", "11", "12", "30", "31", "32", "34", "46", "48", "65", "66", "81", "82"],
            "PDL": ["44", "49", "53", "72", "85"],
            "PAC": ["04", "05", "06", "13", "83", "84"]
        ]
        var out: [String: String] = [:]
        for (region, depts) in table { for d in depts { out[d] = region } }
        return out
    }()

    // MARK: - United Kingdom

    static let unitedKingdom = CountryAtlas(code: "GB", unitName: "Nations", regions: [
        r("GB", "ENG", "England"), r("GB", "SCT", "Scotland"),
        r("GB", "WLS", "Wales", ["Cymru"]), r("GB", "NIR", "Northern Ireland")
    ], colors: [0x2F7CF6, 0xF43F72, 0x7C5CFA])

    // MARK: - Morocco (matched by region or major city)

    static let morocco = CountryAtlas(code: "MA", unitName: "Regions", regions: [
        r("MA", "01", "Tanger-Tétouan-Al Hoceïma", ["Tangier", "Tanger", "Tetouan", "Al Hoceima", "Chefchaouen", "Larache", "Asilah", "Fnideq", "Mdiq", "Ouazzane", "Ksar El Kebir"]),
        r("MA", "02", "Oriental", ["L'Oriental", "Oujda", "Nador", "Berkane", "Saidia", "Taourirt", "Figuig", "Jerada", "Driouch"]),
        r("MA", "03", "Fès-Meknès", ["Fes", "Fez", "Meknes", "Ifrane", "Taza", "Sefrou", "El Hajeb", "Taounate", "Boulemane", "Fez-Meknes"]),
        r("MA", "04", "Rabat-Salé-Kénitra", ["Rabat", "Sale", "Kenitra", "Temara", "Skhirat", "Khemisset", "Sidi Kacem", "Sidi Slimane"]),
        r("MA", "05", "Béni Mellal-Khénifra", ["Beni Mellal", "Khenifra", "Khouribga", "Azilal", "Fquih Ben Salah"]),
        r("MA", "06", "Casablanca-Settat", ["Casablanca", "Settat", "Mohammedia", "El Jadida", "Berrechid", "Benslimane", "Azemmour", "Bouskoura", "Nouaceur", "Mediouna", "Sidi Bennour"]),
        r("MA", "07", "Marrakech-Safi", ["Marrakesh", "Marrakech", "Safi", "Essaouira", "El Kelaa des Sraghna", "Youssoufia", "Chichaoua", "Al Haouz", "Ben Guerir", "Marrakesh-Safi"]),
        r("MA", "08", "Drâa-Tafilalet", ["Errachidia", "Ouarzazate", "Zagora", "Tinghir", "Midelt", "Merzouga", "Rissani"]),
        r("MA", "09", "Souss-Massa", ["Agadir", "Taroudant", "Tiznit", "Inezgane", "Ait Melloul", "Taghazout", "Tata"]),
        r("MA", "10", "Guelmim-Oued Noun", ["Guelmim", "Tan-Tan", "Tan Tan", "Sidi Ifni", "Assa"]),
        r("MA", "11", "Laâyoune-Sakia El Hamra", ["Laayoune", "Boujdour", "Tarfaya", "Smara", "Es-Semara"]),
        r("MA", "12", "Dakhla-Oued Ed-Dahab", ["Dakhla", "Aousserd"])
    ], colors: [0xF43F72, 0xFF5A36, 0x10B5A4])
}

/// Continents for the world-explorer badge.
nonisolated enum WorldCatalog {
    struct Continent: Identifiable, Sendable {
        let id: String
        let name: String
        let symbol: String
        let color: UInt32
        let countries: Set<String>
    }

    static let continents: [Continent] = [
        Continent(id: "AF", name: "Africa", symbol: "sun.max.fill", color: 0xFFAE34, countries: set("DZ AO BJ BW BF BI CV CM CF TD KM CG CD CI DJ EG GQ ER SZ ET GA GM GH GN GW KE LS LR LY MG MW ML MR MU MA MZ NA NE NG RW ST SN SC SL SO ZA SS SD TZ TG TN UG ZM ZW EH")),
        Continent(id: "AS", name: "Asia", symbol: "mountain.2.fill", color: 0xF43F72, countries: set("AF AM AZ BH BD BT BN KH CN GE IN ID IR IQ IL JP JO KZ KW KG LA LB MY MV MN MM NP KP OM PK PS PH QA SA SG KR LK SY TW TJ TH TL TR TM AE UZ VN YE HK MO")),
        Continent(id: "EU", name: "Europe", symbol: "building.columns.fill", color: 0x7C5CFA, countries: set("AL AD AT BY BE BA BG HR CY CZ DK EE FI FR DE GR HU IS IE IT XK LV LI LT LU MT MD MC ME NL MK NO PL PT RO RU SM RS SK SI ES SE CH UA GB VA")),
        Continent(id: "NA", name: "North America", symbol: "tree.fill", color: 0x2F7CF6, countries: set("AG BS BB BZ CA CR CU DM DO SV GD GT HT HN JM MX NI PA KN LC VC TT US PR")),
        Continent(id: "SA", name: "South America", symbol: "leaf.fill", color: 0x4FAE3C, countries: set("AR BO BR CL CO EC GY PY PE SR UY VE")),
        Continent(id: "OC", name: "Oceania", symbol: "water.waves", color: 0x10B5A4, countries: set("AU FJ KI MH FM NR NZ PW PG WS SB TO TV VU"))
    ]

    static var totalCountries: Int { continents.reduce(0) { $0 + $1.countries.count } }

    private static func set(_ s: String) -> Set<String> { Set(s.split(separator: " ").map(String.init)) }
}
