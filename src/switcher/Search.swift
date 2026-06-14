import Foundation

final class Search {
    static func normalizedQuery(_ query: String) -> String {
        SearchTestable.normalize(query).text
    }

    static func matches(_ window: Window, query: String) -> Bool {
        if normalizedQuery(query).isEmpty { return true }
        ensureCache(for: window, originalQuery: query)
        return window.swBestSimilarity > 0
    }

    static func relevance(for window: Window, query: String) -> Double {
        if normalizedQuery(query).isEmpty { return 0 }
        ensureCache(for: window, originalQuery: query)
        return window.swBestSimilarity
    }

    private static func ensureCache(for window: Window, originalQuery: String) {
        // 缓存键用「原始（保留大小写）查询」：tierMatch 按原始查询算"大小写完全匹配"加分；
        // 若用归一化（折叠大小写）做键，"git"→"Git" 会命中旧缓存、丢失大小写加分。两个调用方须传同一原始查询。
        let cacheKey = originalQuery + "|3"
        if window.lastSearchQuery == cacheKey { return }
        let appName = window.application.localizedName ?? ""
        let title = window.title ?? ""
        let appResult = SearchTestable.tierMatch(query: originalQuery, text: appName)
        let titleResult = SearchTestable.tierMatch(query: originalQuery, text: title)
        window.swAppResults = appResult.map { [$0.toSWResult()] } ?? []
        window.swTitleResults = titleResult.map { [$0.toSWResult()] } ?? []
        let appScore = Double(appResult?.score ?? 0)
        let titleScore = Double(titleResult?.score ?? 0)
        window.swBestSimilarity = max(appScore * 1.02, titleScore)
        window.lastSearchQuery = cacheKey
    }
}

