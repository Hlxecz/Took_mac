import SwiftUI
import WidgetKit
import TookCore

struct TookEntry: TimelineEntry {
    let date: Date
    let tasks: [TaskItem]
    var tomorrowPlans: [TaskItem] = []
    var error: String? = nil
}

struct TookProvider: TimelineProvider {
    func placeholder(in context: Context) -> TookEntry {
        TookEntry(date: .now, tasks: [TaskItem(title: "새 계획을 적어 보세요")])
    }

    func getSnapshot(in context: Context, completion: @escaping (TookEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : read())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TookEntry>) -> Void) {
        let now = Date()
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now))!
        do {
            let doc = try SharedTaskStorage.repository().load()
            let entries = [entry(for: now, document: doc), entry(for: tomorrow, document: doc)]
            completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(15 * 60))))
        } catch {
            completion(Timeline(entries: [TookEntry(date: now, tasks: [], error: "앱에서 공유 저장소를 확인해 주세요")],
                                policy: .after(now.addingTimeInterval(60))))
        }
    }

    private func entry(for date: Date, document: TaskDocument) -> TookEntry {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: date)!
        return TookEntry(date: date, tasks: document.pending(on: date), tomorrowPlans: document.scheduled(on: tomorrow))
    }

    private func read() -> TookEntry {
        do { return entry(for: .now, document: try SharedTaskStorage.repository().load()) }
        catch { return TookEntry(date: .now, tasks: [], error: "앱에서 공유 저장소를 확인해 주세요") }
    }
}

struct TookWidgetView: View {
    let entry: TookEntry
    @Environment(\.widgetFamily) private var family
    private let accent = Color(red: 0.97, green: 0.51, blue: 0.43)
    private var limit: Int { family == .systemSmall ? (entry.tomorrowPlans.isEmpty ? 3 : 2) : family == .systemMedium ? 3 : 8 }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("계획")
                    .font(.system(size: family == .systemSmall ? 13 : 16, weight: .bold))
                Spacer(minLength: 3)
                Link(destination: URL(string: "tookmac://add")!) {
                    Image(systemName: "plus").font(.system(size: 12, weight: .semibold)).foregroundStyle(accent)
                }.accessibilityLabel("앱에서 계획 추가")
            }
            if let error = entry.error {
                Text(error).font(.caption).foregroundStyle(.secondary)
            } else if entry.tasks.isEmpty {
                Spacer(minLength: 0)
                HStack(spacing: 7) {
                    Image(systemName: "checkmark").foregroundStyle(accent)
                    Text("남은 계획이 없어요").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            } else {
                ForEach(Array(entry.tasks.prefix(limit))) { task in
                    Button(intent: CompleteTaskIntent(taskID: task.id.uuidString)) {
                        HStack(spacing: 8) {
                            Image(systemName: "circle").font(.system(size: 19, weight: .light)).foregroundStyle(.secondary)
                            if let plan = task.calendarPlan {
                                Text(plan.start.formatted(.dateTime.month().day()) + (plan.isAllDay ? " 종일" : " " + plan.start.formatted(date: .omitted, time: .shortened)))
                                    .font(.system(size: 10)).foregroundStyle(.secondary)
                            }
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
            if let tomorrow = entry.tomorrowPlans.first {
                Text("내일: \(tomorrow.title)\(entry.tomorrowPlans.count > 1 ? " 외 \(entry.tomorrowPlans.count - 1)개" : "")")
                    .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
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
        .description("계획을 바로 보고 체크하세요. 완료할 때까지 남아 있어요.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .containerBackgroundRemovable(true)
    }
}
