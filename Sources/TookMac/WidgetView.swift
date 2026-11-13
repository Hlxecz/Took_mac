import SwiftUI
import TookCore

private let tookBlue = Color(red: 0.97, green: 0.51, blue: 0.43)

struct WidgetView: View {
    @ObservedObject var store: TaskStore
    @ObservedObject var preferences: WidgetPreferences
    @ObservedObject var calendarSync: CalendarSync
    let showSettings: () -> Void
    @State private var tab: TaskTab = .plans
    @State private var title = ""
    @State private var scheduledDate = Date()
    @State private var repeatRule: RepeatRule = .none
    @State private var showOptions = false
    @State private var editingTask: TaskItem?
    @State private var confirmClearHistory = false
    @FocusState private var inputFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    private enum TaskTab: String, CaseIterable { case plans = "계획", upcoming = "예정", history = "기록" }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            content(now: context.date)
        }
        .background {
            ZStack {
                // 배경 화면과 창 포커스에 상관없이 같은 색을 사용한다.
                colorScheme == .dark ? Color(white: 0.118) : Color(white: 0.97)
                LinearGradient(colors: [tookBlue.opacity(0.09), .clear], startPoint: .top, endPoint: .center)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(LinearGradient(colors: [.white.opacity(0.36), .white.opacity(0.10)], startPoint: .topLeading, endPoint: .bottomTrailing)))
        .tint(tookBlue)
        .confirmationDialog("모든 기록을 비울까요?", isPresented: $confirmClearHistory, titleVisibility: .visible) {
            Button("기록 비우기", role: .destructive) {
                _ = store.change("기록을 비웠어요", allowsUndo: false) { $0.clearHistory() }
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("완료 기록과 휴지통에 있는 계획을 모두 영구 삭제합니다. 진행 중인 계획과 예정된 계획은 유지되며, 지운 기록은 복원할 수 없어요.")
        }
        .sheet(item: $editingTask) { task in
            EditTaskView(task: task, store: store)
        }
        .alert("확인이 필요해요", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
            Button("확인") { store.error = nil }
        } message: { Text(store.error ?? "") }
    }

    private func content(now: Date) -> some View {
        let pending = store.document.pending(on: now)
        let upcoming = store.document.upcoming(after: now)
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now))!
        let tomorrowPlans = store.document.scheduled(on: tomorrow)
        let trashed = store.document.history.filter { $0.kind == .deleted }.count
        let historyCount = store.document.history.count
        return VStack(spacing: 0) {
            Spacer().frame(height: 24)
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 14) {
                    Text(tab.rawValue)
                        .font(.system(size: 30, weight: .bold)).tracking(-0.8)
                    Text(tab == .history ? "기록" : "\(tab == .plans ? pending.count : upcoming.count)개의 계획")
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                Button(action: showSettings) {
                    Image(systemName: "ellipsis").font(.system(size: 14, weight: .semibold))
                        .frame(width: 36, height: 36).contentShape(Rectangle())
                }
                    .buttonStyle(.plain).foregroundStyle(.secondary).help("설정").accessibilityLabel("설정")
            }.padding(.horizontal, 24).padding(.top, 4).padding(.bottom, 18)

            HStack(spacing: 4) {
                ForEach(TaskTab.allCases, id: \.self) { item in
                    Button { tab = item } label: {
                        Text(item.rawValue).font(.system(size: 12, weight: tab == item ? .semibold : .medium))
                            .frame(maxWidth: .infinity).padding(.vertical, 9)
                            .contentShape(Rectangle())
                            .background(tab == item ? tookBlue.opacity(0.10) : .clear, in: RoundedRectangle(cornerRadius: 8))
                            .foregroundStyle(tab == item ? tookBlue : .secondary)
                    }.buttonStyle(.plain).accessibilityAddTraits(tab == item ? .isSelected : [])
                }
            }.padding(.horizontal, 20).padding(.bottom, 12)

            if !calendarSync.authorized && !calendarSync.selectedIDs.isEmpty {
                HStack {
                    Label("캘린더 접근 권한을 다시 허용해 주세요", systemImage: "calendar.badge.exclamationmark")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    Spacer(minLength: 4)
                    Button("다시 연결") { calendarSync.connect() }.font(.system(size: 11))
                        .disabled(calendarSync.requesting)
                }.padding(.horizontal, 24).padding(.bottom, 10)
            }
            if store.loadFailed {
                VStack(spacing: 12) {
                    Image(systemName: "externaldrive.badge.exclamationmark").font(.largeTitle).foregroundStyle(.secondary)
                    Text("저장 파일을 확인해 주세요").font(.headline)
                    Text("기존 파일을 보호하기 위해 편집을 멈췄어요.").font(.caption).foregroundStyle(.secondary)
                    Button("다시 불러오기") { store.reload() }
                    Button("저장 폴더 열기") { store.openDataFolder() }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if tab == .history {
                            HStack {
                                Text(historyCount == 0 ? "기록이 비어 있어요" : "완료 \(historyCount - trashed)개 · 휴지통 \(trashed)개")
                                    .font(.system(size: 11)).foregroundStyle(.secondary)
                                Spacer()
                                Button("기록 비우기", role: .destructive) { confirmClearHistory = true }
                                    .font(.system(size: 11)).buttonStyle(.plain)
                                    .disabled(historyCount == 0)
                            }.padding(.vertical, 10)
                            if store.document.history.isEmpty {
                                emptyState(symbol: "clock.arrow.circlepath", title: "아직 기록이 없어요", detail: "완료하거나 지운 계획을 여기서 복원해요.")
                            }
                            ForEach(store.document.history) { record in historyRow(record) }
                        } else {
                            let items = tab == .plans ? pending : upcoming
                            if items.isEmpty {
                                emptyState(symbol: tab == .plans ? "checkmark" : "calendar",
                                    title: tab == .plans ? "남은 계획이 없어요" : "예정된 계획이 없어요",
                                    detail: tab == .plans ? "새 계획을 적어 보세요. 완료할 때까지 여기에 남아요." : "계획을 추가할 때 미래 날짜를 골라 보세요.")
                            }
                            ForEach(items) { task in
                                if tab == .plans {
                                    taskRow(task, now: now)
                                        .draggable(task.id.uuidString)
                                        .dropDestination(for: String.self) { ids, _ in
                                            guard let text = ids.first, let source = UUID(uuidString: text),
                                                  source != task.id, pending.contains(where: { $0.id == source }) else { return false }
                                            return store.change("계획 순서를 바꿨어요") { $0.move(id: source, to: task.id) }
                                        }
                                        .accessibilityAction(named: "위로 이동") { move(task, in: items, direction: -1) }
                                        .accessibilityAction(named: "아래로 이동") { move(task, in: items, direction: 1) }
                                } else { taskRow(task, now: now) }
                            }
                            if tab == .plans && !tomorrowPlans.isEmpty {
                                VStack(alignment: .leading, spacing: 7) {
                                    Label("내일은 이런 계획이 잡혀 있습니다", systemImage: "calendar")
                                        .font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                                    ForEach(tomorrowPlans.prefix(3)) { task in
                                        Text(task.title).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                    Button(tomorrowPlans.count > 3 ? "외 \(tomorrowPlans.count - 3)개 · 예정에서 보기" : "예정에서 보기") { tab = .upcoming }
                                        .font(.system(size: 10)).buttonStyle(.plain).foregroundStyle(tookBlue)
                                }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
                                    .background(.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 12))
                                    .padding(.top, 16)
                            }
                        }
                    }.padding(.horizontal, 24).padding(.bottom, 12)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            VStack(spacing: 10) {
                if let notice = store.notice {
                    HStack(spacing: 6) {
                        Text(notice).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                        Spacer(minLength: 0)
                        if store.undoDocument != nil {
                            Button("되돌리기") { animate { store.undo() } }.font(.system(size: 11, weight: .semibold)).buttonStyle(.plain).foregroundStyle(tookBlue)
                        }
                        Button { store.dismissNotice() } label: { Image(systemName: "xmark").font(.system(size: 9)).frame(width: 20, height: 20) }.buttonStyle(.plain).accessibilityLabel("알림 닫기")
                    }
                }
                if showOptions {
                    HStack {
                        DatePicker("날짜", selection: $scheduledDate, displayedComponents: .date).labelsHidden().datePickerStyle(.field).accessibilityLabel("계획 날짜")
                        Spacer()
                        Picker("반복", selection: $repeatRule) {
                            ForEach(RepeatRule.allCases, id: \.self) { Text($0.title).tag($0) }
                        }.labelsHidden().frame(width: 115)
                    }.font(.system(size: 11))
                }
                HStack(spacing: 7) {
                    TextField("새로운 계획", text: $title)
                        .textFieldStyle(.plain).font(.system(size: 13)).focused($inputFocused)
                        .onSubmit(addTask).accessibilityLabel("새 계획")
                    Button { showOptions.toggle() } label: {
                        Image(systemName: showOptions || repeatRule != .none ? "calendar.badge.clock" : "calendar").frame(width: 25, height: 28)
                    }.buttonStyle(.plain).foregroundStyle(showOptions ? tookBlue : .secondary).help("날짜와 반복 설정").accessibilityLabel("날짜와 반복 설정")
                    Button(action: addTask) {
                        Image(systemName: "plus").font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                            .frame(width: 28, height: 28).background(tookBlue, in: RoundedRectangle(cornerRadius: 8))
                    }.buttonStyle(.plain).disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).accessibilityLabel("계획 추가")
                }.padding(.horizontal, 12).padding(.vertical, 8)
                    .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(inputFocused ? tookBlue.opacity(0.5) : .clear))
                    .disabled(store.loadFailed)
            }.padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 16)
        }
        .frame(minWidth: 330, minHeight: 400)
    }

    private func taskRow(_ task: TaskItem, now: Date) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Button {
                animate { _ = store.change("계획을 완료했어요") { $0.complete(id: task.id) } }
            } label: {
                Image(systemName: "circle").font(.system(size: 22, weight: .light)).foregroundStyle(.secondary.opacity(0.6)).frame(width: 24, height: 25)
            }.buttonStyle(.plain).accessibilityLabel("\(task.title) 완료")
                .disabled(!task.isReady(on: now))
            VStack(alignment: .leading, spacing: 5) {
                Text(task.title).font(.system(size: 14, weight: .medium)).fixedSize(horizontal: false, vertical: true)
                if let plan = task.calendarPlan {
                    Label("\(plan.calendarTitle) · \(plan.isAllDay ? "종일" : plan.start.formatted(date: .omitted, time: .shortened))", systemImage: "calendar")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
                if task.repeatRule != .none || tab == .upcoming || task.calendarPlan != nil {
                    HStack(spacing: 5) {
                        if task.repeatRule != .none {
                            Image(systemName: "repeat"); Text(task.repeatRule.title)
                        }
                        if tab == .upcoming || task.calendarPlan != nil { Text(task.scheduledDate, format: .dateTime.month().day().locale(Locale(identifier: "ko_KR"))) }
                    }.font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 3)
            if tab == .plans {
                Image(systemName: "line.3.horizontal").font(.system(size: 10)).foregroundStyle(.tertiary)
                    .padding(.top, 8).help("계획을 끌어서 순서를 바꿀 수 있어요")
            }
            Menu {
                Button(task.calendarPlan == nil ? "수정" : "캘린더에서 수정", systemImage: "pencil") { editingTask = task }
                    .disabled(task.calendarPlan != nil)
                Button("내일로 미루기", systemImage: "calendar") {
                    _ = store.change("내일 계획으로 옮겼어요") {
                        try $0.edit(id: task.id, title: task.title, scheduledDate: Calendar.current.date(byAdding: .day, value: 1, to: Date())!, repeatRule: task.repeatRule)
                    }
                }.disabled(task.calendarPlan != nil)
                Button("휴지통으로", systemImage: "trash", role: .destructive) {
                    animate { _ = store.change("휴지통으로 옮겼어요") { $0.delete(id: task.id) } }
                }
            } label: { Image(systemName: "ellipsis").frame(width: 18, height: 25) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().foregroundStyle(.secondary).accessibilityLabel("\(task.title) 메뉴")
        }.padding(.vertical, 12).padding(.horizontal, 12)
            .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.08)))
            .padding(.bottom, 8)
    }

    private func historyRow(_ record: ActivityRecord) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: record.kind == .completed ? "checkmark.circle.fill" : "trash")
                .foregroundStyle(record.kind == .completed ? tookBlue.opacity(0.6) : .secondary).frame(width: 24, height: 23)
            VStack(alignment: .leading, spacing: 4) {
                Text(record.task.title).font(.system(size: 13)).strikethrough(record.kind == .completed).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Text("\(record.date.formatted(.dateTime.month().day().hour().minute().locale(Locale(identifier: "ko_KR")))) · \(record.kind == .completed ? "완료" : "휴지통")")
                    .font(.system(size: 10)).foregroundStyle(.tertiary)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Button("복원") { animate { _ = store.change("계획을 복원했어요") { $0.restore(recordID: record.id) } } }
                .font(.system(size: 11)).buttonStyle(.plain).foregroundStyle(tookBlue).padding(.top, 4)
                .accessibilityLabel("\(record.task.title) 복원")
        }.padding(.vertical, 12)
    }

    private func emptyState(symbol: String, title: String, detail: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 25, weight: .light)).foregroundStyle(tookBlue.opacity(0.7))
                .frame(width: 58, height: 58).background(tookBlue.opacity(0.055), in: Circle())
            Text(title).font(.system(size: 14, weight: .semibold))
            Text(detail).font(.system(size: 11)).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity).padding(.vertical, 38)
    }

    private func addTask() {
        if store.change("계획을 추가했어요", { try $0.add(title: title, scheduledDate: showOptions ? scheduledDate : Date(), repeatRule: repeatRule) }) {
            tab = Calendar.current.startOfDay(for: showOptions ? scheduledDate : Date()) > Calendar.current.startOfDay(for: Date()) ? .upcoming : .plans
            title = ""; scheduledDate = Date(); repeatRule = .none; showOptions = false
            inputFocused = true
        }
    }

    private func move(_ task: TaskItem, in items: [TaskItem], direction: Int) {
        guard let index = items.firstIndex(where: { $0.id == task.id }), items.indices.contains(index + direction) else { return }
        _ = store.change("계획 순서를 바꿨어요") { $0.move(id: task.id, to: items[index + direction].id) }
    }

    private func animate(_ action: () -> Void) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18), action)
    }
}

struct EditTaskView: View {
    let task: TaskItem
    @ObservedObject var store: TaskStore
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var date: Date
    @State private var rule: RepeatRule
    init(task: TaskItem, store: TaskStore) {
        self.task = task; self.store = store
        _title = State(initialValue: task.title)
        _date = State(initialValue: task.scheduledDate)
        _rule = State(initialValue: task.repeatRule)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("계획 수정").font(.title3.bold())
            TextField("계획", text: $title).textFieldStyle(.roundedBorder)
            DatePicker("날짜", selection: $date, displayedComponents: .date)
            Picker("반복", selection: $rule) { ForEach(RepeatRule.allCases, id: \.self) { Text($0.title).tag($0) } }
            HStack {
                Spacer()
                Button("취소") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("저장") {
                    if store.change("계획을 수정했어요", { try $0.edit(id: task.id, title: title, scheduledDate: date, repeatRule: rule) }) { dismiss() }
                }.keyboardShortcut(.defaultAction).disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(24).frame(width: 320)
    }
}
