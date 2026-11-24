import Foundation

struct Storefront: Identifiable, Hashable {
    let id: String      // Apple Storefront numeric ID (e.g. "143441")
    let code: String    // ISO-2 country code (e.g. "US")
    let name: String    // Display name
    let flag: String

    static let accountDefault = Storefront(id: "", code: "AUTO", name: "Mặc định tài khoản", flag: "🌐")

    static let all: [Storefront] = [
        .accountDefault,
        Storefront(id: "143471", code: "VN", name: "Vietnam", flag: "🇻🇳"),
        Storefront(id: "143441", code: "US", name: "United States", flag: "🇺🇸"),
        Storefront(id: "143462", code: "JP", name: "Japan", flag: "🇯🇵"),
        Storefront(id: "143466", code: "KR", name: "South Korea", flag: "🇰🇷"),
        Storefront(id: "143465", code: "CN", name: "China", flag: "🇨🇳"),
        Storefront(id: "143463", code: "HK", name: "Hong Kong", flag: "🇭🇰"),
        Storefront(id: "143470", code: "TW", name: "Taiwan", flag: "🇹🇼"),
        Storefront(id: "143464", code: "SG", name: "Singapore", flag: "🇸🇬"),
        Storefront(id: "143444", code: "GB", name: "United Kingdom", flag: "🇬🇧"),
        Storefront(id: "143455", code: "CA", name: "Canada", flag: "🇨🇦"),
        Storefront(id: "143460", code: "AU", name: "Australia", flag: "🇦🇺"),
        Storefront(id: "143443", code: "DE", name: "Germany", flag: "🇩🇪"),
        Storefront(id: "143442", code: "FR", name: "France", flag: "🇫🇷"),
        Storefront(id: "143469", code: "RU", name: "Russia", flag: "🇷🇺"),
        Storefront(id: "143467", code: "IN", name: "India", flag: "🇮🇳"),
        Storefront(id: "143503", code: "BR", name: "Brazil", flag: "🇧🇷"),
        Storefront(id: "143475", code: "TH", name: "Thailand", flag: "🇹🇭"),
        Storefront(id: "143476", code: "ID", name: "Indonesia", flag: "🇮🇩"),
        Storefront(id: "143473", code: "MY", name: "Malaysia", flag: "🇲🇾"),
        Storefront(id: "143474", code: "PH", name: "Philippines", flag: "🇵🇭"),
        Storefront(id: "143480", code: "TR", name: "Turkey", flag: "🇹🇷"),
    ]
}
