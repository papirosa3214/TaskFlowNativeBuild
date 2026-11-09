import Foundation

/// База знаний — смысловой поиск по документации всех проектов.
///
/// За ручками `/api/knowledge/*` стоит RAGFlow на .110 (датасет «TaskFlow —
/// документация»), но приложение об этом не знает и знать не должно: ключ
/// RAGFlow живёт на сервере, сюда ходим обычным токеном TaskFlow. Документы
/// в индекс складывает `~/kb/taskflow_docs_ragflow_sync.py` раз в сутки.
///
/// Поиск отвечает КУСКАМИ текста — так устроен retrieval. У каждого куска
/// есть `docId` — идентификатор настоящей заметки в TaskFlow, по нему
/// открывается оригинал (`AppRoute.noteEditor`), а не копия из индекса.
public struct ApiKnowledgeChunk: Decodable, Identifiable, Sendable, Hashable {
    /// Своего идентификатора у куска нет — собираем из документа и текста,
    /// чтобы `ForEach` не путал соседние фрагменты одного документа.
    public var id: String { (docId ?? documentName) + "#" + String(text.prefix(24)) }
    public let text: String
    public let score: Double?
    public let documentName: String
    /// Название заметки и проект — сервер подмешивает их из TaskFlow: в самом
    /// индексе документ зовётся `taskflow-<uuid>.md`.
    public let title: String?
    public let project: String?
    public let docId: String?

    enum CodingKeys: String, CodingKey {
        case text, score, title, project
        case documentName = "document_name"
        case docId = "doc_id"
    }
}

public struct ApiKnowledgeDocument: Decodable, Identifiable, Sendable, Hashable {
    public var id: String { ragflowId }
    public let name: String
    public let title: String?
    public let project: String?
    /// Заметки в TaskFlow больше нет, а в индексе она осталась — документация
    /// закрытого проекта. Открывается только из индекса.
    public let archived: Bool
    public let docId: String?
    public let ragflowId: String
    public let chunkCount: Int?
    public let size: Int?
    public let updatedAt: String?
    /// `false` — документ ещё индексируется и в поиске пока не участвует.
    public let indexed: Bool

    enum CodingKeys: String, CodingKey {
        case name, size, title, project, archived
        case docId = "doc_id"
        case ragflowId = "ragflow_id"
        case chunkCount = "chunk_count"
        case updatedAt = "updated_at"
        case indexed
    }
}

/// Датасет RAGFlow — «полка», на которую ложится документация проекта.
/// Разделение нужно, чтобы специфический проект не подмешивал свои документы
/// туда, где ищут рабочее (владелец 08.09.2026).
///
/// С 09.11.2026 список датасетов — главный экран базы знаний: владелец сам
/// включает и исключает датасеты, раскладывает их по разделам и выдаёт
/// доступ ролям. Поэтому здесь же живут `enabled`, `section` и `roles`.
public struct ApiKnowledgeDataset: Decodable, Identifiable, Sendable, Hashable {
    public let id: String
    public let name: String
    public let documentCount: Int?
    /// Датасет, куда попадают проекты без собственного выбора.
    public let isDefault: Bool
    public let chunkCount: Int?
    /// `taskflow` — датасет, который наполняет сам TaskFlow (общий и
    /// проектные); `other` — чужие синки. По имени это не определить: «Память
    /// — заметки» звучит как наша, но её наполняет другой синк.
    public let owner: String?
    /// Выключен — датасета для TaskFlow нет: ни поиска, ни загрузки.
    public let enabled: Bool?
    public let section: KnowledgeSection?
    /// Кому выдан доступ. Пусто — только владельцу.
    public let roles: [KnowledgeRole]?

    enum CodingKeys: String, CodingKey {
        case id, name, owner, enabled, section, roles
        case documentCount = "document_count"
        case isDefault = "is_default"
        case chunkCount = "chunk_count"
    }

    /// Явный инициализатор: новый датасет после `POST /knowledge/datasets`
    /// приходит коротким ответом `{id, name}`, остальное приложение узнает
    /// при следующем чтении списка.
    public init(
        id: String,
        name: String,
        documentCount: Int?,
        isDefault: Bool,
        chunkCount: Int? = nil,
        owner: String? = nil,
        enabled: Bool? = nil,
        section: KnowledgeSection? = nil,
        roles: [KnowledgeRole]? = nil
    ) {
        self.id = id
        self.name = name
        self.documentCount = documentCount
        self.isDefault = isDefault
        self.chunkCount = chunkCount
        self.owner = owner
        self.enabled = enabled
        self.section = section
        self.roles = roles
    }

    public var isEnabled: Bool { enabled ?? true }
    public var isTaskflowOwned: Bool { owner == "taskflow" }
    public var roleTitles: [String] { (roles ?? []).map(\.title) }
}

/// База знаний как шлюз к RAGFlow (владелец 09.11.2026).
///
/// Раньше экран «База знаний» был дневником заметок с поиском. Теперь это
/// список ДАТАСЕТОВ RAGFlow: тематика → документы → вопрос по ним. Заметки
/// TaskFlow — лишь одна из полок («Заметки TaskFlow»), а не весь экран.
///
/// Телефон ничего не решает и ничего не индексирует: он показывает то, что
/// отдал сервер, и отправляет ввод обратно (правило тонкого клиента).

/// Раздел базы знаний — папка датасетов по теме. Заводит владелец.
public struct KnowledgeSection: Decodable, Identifiable, Sendable, Hashable {
    public let id: Int
    public let title: String
    public let position: Int?
    /// Сколько ВКЛЮЧЁННЫХ датасетов в разделе — сервер считает сам.
    public let datasetCount: Int?

    enum CodingKeys: String, CodingKey {
        case id, title, position
        case datasetCount = "dataset_count"
    }
}

/// Роль, которой выдан доступ к датасету. Пустой список — датасет выдан
/// только владельцу.
public struct KnowledgeRole: Decodable, Identifiable, Sendable, Hashable {
    public var id: String { key }
    public let key: String
    public let title: String
}

/// Ход разбора документа в индексе. `run`: DONE — в поиске участвует,
/// RUNNING — ещё разбирается, FAIL — сорвался (тогда `message` говорит почему).
public struct KnowledgeDocumentStatus: Decodable, Sendable, Hashable {
    public let id: String
    public let name: String
    public let run: String?
    public let progress: Double?
    public let message: String?
    public let chunkCount: Int?

    public var isIndexed: Bool { run == "DONE" }
    public var isFailed: Bool { run == "FAIL" }

    enum CodingKeys: String, CodingKey {
        case id, name, run, progress, message
        case chunkCount = "chunk_count"
    }
}

/// Ответ на вопрос по базе знаний: текст модели и куски, на которые она
/// опиралась. `answer == nil` — модель недоступна или ничего не нашлось:
/// куски всё равно показываем, человек прочитает источник сам.
public struct KnowledgeAnswer: Decodable, Sendable, Hashable {
    public let question: String
    public let answer: String?
    public let model: String?
    public let chunks: [ApiKnowledgeChunk]
    public let hint: String?

    enum CodingKeys: String, CodingKey {
        case question, answer, model, chunks, hint
    }
}

// ── Раскладка полок и состояние заметки в индексе ──────────────────────────
// Это чистая логика без сети и без SwiftUI: её проверяет
// `Tools/test_knowledge_base.py` (компилирует этот файл и гоняет проверки).

/// Датасет в том виде, в каком он нужен раскладке: на экране их приходит
/// полный список с сервера, а порядок полок решается здесь.
public struct KnowledgeDatasetRef: Sendable, Hashable {
    public let id: String
    public let sectionId: Int?
    public let enabled: Bool

    public init(id: String, sectionId: Int?, enabled: Bool) {
        self.id = id
        self.sectionId = sectionId
        self.enabled = enabled
    }
}

/// Одна полка на экране базы знаний: раздел владельца либо «Без раздела».
public struct KnowledgeShelf: Identifiable, Sendable, Hashable {
    public let id: String
    public let title: String
    public let sectionId: Int?
    /// Датасеты полки в порядке сервера — порядок RAGFlow не переупорядочиваем.
    public let datasetIds: [String]

    public init(id: String, title: String, sectionId: Int?, datasetIds: [String]) {
        self.id = id
        self.title = title
        self.sectionId = sectionId
        self.datasetIds = datasetIds
    }
}

public enum KnowledgeLibrary {
    /// Разделы идут в порядке владельца (`position`, затем `id` — сервер уже
    /// отсортировал), «Без раздела» всегда последняя.
    ///
    /// Исключённый датасет не попадает никуда: владелец выключил его — значит
    /// этого датасета для TaskFlow нет, а не «спрятать в конец списка».
    public static func shelves(
        datasets: [KnowledgeDatasetRef],
        sections: [KnowledgeSection]
    ) -> [KnowledgeShelf] {
        let visible = datasets.filter(\.enabled)
        var shelves: [KnowledgeShelf] = []
        for section in sections {
            // Пустой раздел оставляем: владелец мог только что его создать и
            // ещё не разложил датасеты — иначе раздел «исчезает» из списка.
            shelves.append(
                KnowledgeShelf(
                    id: "section-\(section.id)",
                    title: section.title,
                    sectionId: section.id,
                    datasetIds: visible.filter { $0.sectionId == section.id }.map(\.id)
                )
            )
        }
        let unsectioned = visible.filter { $0.sectionId == nil }.map(\.id)
        if !unsectioned.isEmpty {
            shelves.append(
                KnowledgeShelf(id: "unsectioned", title: "Без раздела", sectionId: nil, datasetIds: unsectioned)
            )
        }
        return shelves
    }
}

/// Состояние заметки в индексе — тот же язык, что у сервера (`index_state`
/// в `GET /api/notes`): `indexed` / `queued` / `indexing` / `error`.
public enum NoteIndexState: String, Sendable, Hashable {
    case indexed
    case queued
    case indexing
    case error
    /// Сервер не сказал ничего — заметка лежит в индексе от суточного прогона.
    case unknown

    public init(server: String?) {
        self = NoteIndexState(rawValue: server ?? "") ?? .unknown
    }

    /// Что видит человек в карточке. «В поиске» — это про смысловой поиск,
    /// а не про то, что заметка просто сохранена.
    public var label: String {
        switch self {
        case .indexed: return "В поиске"
        case .queued: return "В очереди на индексацию"
        case .indexing: return "Индексируется"
        case .error: return "Не попала в поиск"
        case .unknown: return "В поиске"
        }
    }

    /// Значок рядом с заметкой — нужен только тому, чего человек не ждёт.
    public var needsAttention: Bool {
        switch self {
        case .queued, .indexing, .error: return true
        case .indexed, .unknown: return false
        }
    }
}
