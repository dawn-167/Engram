import Foundation

// MARK: - 学习内容库服务（数据驱动：新增词库/句库只需往 Resources/data 放 JSON，零代码改动）
// Services 层：只负责从 bundle 读取并解析内容，不依赖 UI。

protocol ContentLibraryServiceProtocol {
    /// 所有单词词库
    var wordDecks: [Deck] { get }
    /// 所有句库（含造句与口语）
    var sentenceDecks: [Deck] { get }
    /// 指定词库中的全部单词
    func words(in deckId: String) -> [WordEntry]
    /// 指定句库中的全部句子
    func sentences(in deckId: String) -> [SentenceEntry]
    /// 按 id 查单词
    func word(by id: String) -> WordEntry?
    /// 按 id 查句子
    func sentence(by id: String) -> SentenceEntry?
    /// 全部单词
    func allWords() -> [WordEntry]
    /// 全部句子
    func allSentences() -> [SentenceEntry]
}

final class ContentLibraryService: ContentLibraryServiceProtocol {

    // MARK: - 属性

    private(set) var wordDecks: [Deck] = []
    private(set) var sentenceDecks: [Deck] = []
    private var wordsByDeck: [String: [WordEntry]] = [:]
    private var sentencesByDeck: [String: [SentenceEntry]] = [:]
    private var wordIndex: [String: WordEntry] = [:]
    private var sentenceIndex: [String: SentenceEntry] = [:]
    private let decoder = JSONDecoder()

    // MARK: - 初始化

    /// - Parameter dataDirectory: 内容目录，默认取 app bundle 的 Resources/data
    init(dataDirectory: URL? = nil) {
        let dir = dataDirectory
            ?? Bundle.main.resourceURL?.appendingPathComponent("data", isDirectory: true)
        if let dir { load(from: dir) }
    }

    // MARK: - 公开方法

    func words(in deckId: String) -> [WordEntry] { wordsByDeck[deckId] ?? [] }

    func sentences(in deckId: String) -> [SentenceEntry] { sentencesByDeck[deckId] ?? [] }

    func word(by id: String) -> WordEntry? { wordIndex[id] }

    func sentence(by id: String) -> SentenceEntry? { sentenceIndex[id] }

    func allWords() -> [WordEntry] { wordsByDeck.values.flatMap { $0 } }

    func allSentences() -> [SentenceEntry] { sentencesByDeck.values.flatMap { $0 } }

    // MARK: - 私有方法

    private func load(from directory: URL) {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: directory,
                                                      includingPropertiesForKeys: nil) else { return }
        for url in files where url.pathExtension == "json" {
            guard let data = try? Data(contentsOf: url) else { continue }
            // 一个文件要么是词库要么是句库，解析失败则跳过并打印日志，不影响其他内容
            if let wordFile = try? decoder.decode(WordDeckFile.self, from: data) {
                ingest(wordFile)
            } else if let sentenceFile = try? decoder.decode(SentenceDeckFile.self, from: data) {
                ingest(sentenceFile)
            } else {
                NSLog("[Engram] 内容文件无法解析，已跳过：\(url.lastPathComponent)")
            }
        }
        wordDecks.sort { $0.id < $1.id }
        sentenceDecks.sort { $0.id < $1.id }
    }

    private func ingest(_ file: WordDeckFile) {
        wordDecks.append(file.deck)
        wordsByDeck[file.deck.id] = file.words
        for word in file.words { wordIndex[word.id] = word }
    }

    private func ingest(_ file: SentenceDeckFile) {
        sentenceDecks.append(file.deck)
        sentencesByDeck[file.deck.id] = file.sentences
        for sentence in file.sentences { sentenceIndex[sentence.id] = sentence }
    }
}
