import SwiftUI
import WidgetKit
import TookCore

struct TookEntry: TimelineEntry {
    let date: Date
    let tasks: [TaskItem]
    var error: String? = nil
}

struct TookProvider: TimelineProvider {
    func placeholder(in context: Context) -> TookEntry {
        TookEntry(date: .now, tasks: [TaskItem(title: "할 일을 툭, 적어 보세요")])
    }

    func getSnapshot(in context: Context, completion: @escaping (TookEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : read())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TookEntry>) -> Void) {
        let now = Date()
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now))!
        do {
            let doc = try SharedTaskStorage.repository().load()
            let entries = [TookEntry(date: now, tasks: doc.pending(on: now)),
                           TookEntry(date: tomorrow, tasks: doc.pending(on: tomorrow))]
            completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(15 * 60))))
        } catch {
            completion(Timeline(entries: [TookEntry(date: now, tasks: [], error: "앱에서 공유 저장소를 확인해 주세요")],
                                policy: .after(now.addingTimeInterval(60))))
        }
    }

    private func read() -> TookEntry {
        do { return TookEntry(date: .now, tasks: try SharedTaskStorage.repository().load().pending(on: .now)) }
        catch { return TookEntry(date: .now, tasks: [], error: "앱에서 공유 저장소를 확인해 주세요") }
    }
}

struct TookWidgetView: View {
    let entry: TookEntry
    @Environment(\.widgetFamily) private var family
    private let accent = Color(red: 0.97, green: 0.51, blue: 0.43)
    private var limit: Int { family == .systemSmall ? 3 : family == .systemMedium ? 3 : 8 }

    var body: some View {
        VStack(alignment: .leading, spacing: family == .systemSmall ? 10 : 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(entry.date, format: .dateTime.month().day().weekday(.wide).locale(Locale(identifier: "ko_KR")))
                    .font(.system(size: family == .systemSmall ? 13 : 16, weight: .bold))
                Spacer(minLength: 3)
                Link(destination: URL(string: "tookmac://add")!) {
                    Image(systemName: "plus").font(.system(size: 12, weight: .semibold)).foregroundStyle(accent)
                }.accessibilityLabel("앱에서 할 일 추가")
            }
            if let error = entry.error {
                Text(error).font(.caption).foregroundStyle(.secondary)
            } else if entry.tasks.isEmpty {
                Spacer(minLength: 0)
                HStack(spacing: 7) {
                    Image(systemName: "checkmark").foregroundStyle(accent)
                    Text("지금 남은 할 일이 없어요").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            } else {
                ForEach(Array(entry.tasks.prefix(limit))) { task in
                    Button(intent: CompleteTaskIntent(taskID: task.id.uuidString)) {
                        HStack(spacing: 8) {
                            Image(systemName: "circle").font(.system(size: 19, weight: .light)).foregroundStyle(.secondary)
                            Text(task.title).font(.system(size: family == .systemSmall ? 12 : 14, weight: .medium))
                                .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                        }.contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityLabel("\(task.title) 완료")
                }
                Spacer(minLength: 0)
            }
            if entry.tasks.count > limit {
                Link("외 \(entry.tasks.count - limit)개 · 앱에서 보기", destination: URL(string: "tookmac://list")!)
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
        .containerBackground(for: .widget) { Color.clear }
        .widgetURL(URL(string: "tookmac://list"))
    }
}

@main
struct TookWidgets: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: SharedTaskStorage.widgetKind, provider: TookProvider()) { entry in
            TookWidgetView(entry: entry)
        }
        .configurationDisplayName("Took Mac")
        .description("오늘 할 일을 바로 보고, 체크해서 완료하세요.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .containerBackgroundRemovable(true)
    }
}
