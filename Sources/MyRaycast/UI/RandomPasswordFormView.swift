import Foundation
import SwiftUI

/// random-passwd 插件的原生表单。命令参数仍由插件解析；这里提供更适合鼠标和键盘的快捷入口。
struct RandomPasswordFormView: View {
    let initialArguments: String
    let focusRequest: Int
    let executor: ActionExecutor

    @State private var length: String
    @State private var letters: Bool
    @State private var numbers: Bool
    @State private var symbols: Bool
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case length, letters, numbers, symbols, generate
    }

    private struct Payload: Encodable {
        let length: Int
        let letters: Bool
        let numbers: Bool
        let symbols: Bool
    }

    init(initialArguments: String, focusRequest: Int, executor: ActionExecutor) {
        self.initialArguments = initialArguments
        self.focusRequest = focusRequest
        self.executor = executor
        let options = Self.parseInitialArguments(initialArguments)
        _length = State(initialValue: String(options.length))
        _letters = State(initialValue: options.letters)
        _numbers = State(initialValue: options.numbers)
        _symbols = State(initialValue: options.symbols)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "key.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(CyberpunkTheme.matrix)
                    .frame(width: 28, height: 28)
                    .background(CyberpunkTheme.surface, in: RoundedRectangle(cornerRadius: 7))
                    .overlay {
                        RoundedRectangle(cornerRadius: 7)
                            .strokeBorder(CyberpunkTheme.border.opacity(0.75), lineWidth: 1)
                    }

                VStack(alignment: .leading, spacing: 2) {
                    Text("生成随机密码")
                        .font(CyberpunkTheme.monoFont(size: 16, weight: .semibold))
                    Text("使用系统安全随机源，生成后自动复制且不进入剪贴板历史")
                        .font(.system(size: 11))
                        .foregroundStyle(CyberpunkTheme.secondaryText)
                }
            }

            VStack(spacing: 10) {
                HStack {
                    Label("密码长度", systemImage: "character.cursor.ibeam")
                    Spacer()
                    TextField("4–256", text: $length)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 92)
                        .focused($focusedField, equals: .length)
                        .onSubmit(generate)
                        .accessibilityLabel("密码长度")
                }

                Divider().opacity(0.35)

                optionToggle("包含字母", detail: "a–z、A–Z", icon: "textformat", value: $letters, field: .letters)
                optionToggle("包含数字", detail: "0–9", icon: "number", value: $numbers, field: .numbers)
                optionToggle("包含符号", detail: "! @ # $ % 等", icon: "number.square", value: $symbols, field: .symbols)
            }
            .font(CyberpunkTheme.monoFont(size: 13))
            .padding(14)
            .background(CyberpunkTheme.surface.opacity(0.92), in: RoundedRectangle(cornerRadius: 11))
            .overlay {
                RoundedRectangle(cornerRadius: 11)
                    .strokeBorder(CyberpunkTheme.border.opacity(0.78), lineWidth: 1)
            }

            HStack {
                if let validationMessage {
                    Label(validationMessage, systemImage: "exclamationmark.circle")
                        .font(.system(size: 11))
                        .foregroundStyle(CyberpunkTheme.amber)
                } else {
                    Text("Tab / Shift+Tab 切换选项，空格切换开关")
                        .font(CyberpunkTheme.monoFont(size: 11))
                        .foregroundStyle(CyberpunkTheme.mutedText)
                }

                Spacer()

                Button(action: generate) {
                    Label("生成并复制", systemImage: "doc.on.clipboard")
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(CyberpunkTheme.matrix)
                .controlSize(.large)
                .disabled(validationMessage != nil)
                .focused($focusedField, equals: .generate)
                .keyboardShortcut(.return, modifiers: [])
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            FormTabKeyMonitor { backward in
                moveFocus(backward: backward)
            }
        }
        .background(CyberpunkTheme.panelBackground)
        .tint(CyberpunkTheme.matrix)
        .preferredColorScheme(.dark)
        .onAppear { requestLengthFocus() }
        .onChange(of: focusRequest) { _, _ in requestLengthFocus() }
    }

    @ViewBuilder
    private func optionToggle(
        _ title: String,
        detail: String,
        icon: String,
        value: Binding<Bool>,
        field: Field
    ) -> some View {
        Toggle(isOn: value) {
            HStack {
                Label(title, systemImage: icon)
                Spacer()
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(CyberpunkTheme.mutedText)
            }
        }
        .toggleStyle(.switch)
        .focused($focusedField, equals: field)
        .accessibilityHint("按空格切换")
    }

    private var parsedLength: Int? {
        Int(length.trimmingCharacters(in: .whitespaces))
    }

    private var validationMessage: String? {
        guard let parsedLength else { return "长度必须是整数" }
        guard (4...256).contains(parsedLength) else { return "长度范围为 4–256" }
        guard letters || numbers || symbols else { return "至少选择一种字符类型" }
        let required = (letters ? 2 : 0) + (numbers ? 1 : 0) + (symbols ? 1 : 0)
        guard parsedLength >= required else { return "当前组合至少需要 \(required) 位" }
        return nil
    }

    private func generate() {
        guard validationMessage == nil, let parsedLength else { return }
        let payload = Payload(length: parsedLength, letters: letters, numbers: numbers, symbols: symbols)
        guard let data = try? JSONEncoder().encode(payload),
              let text = String(data: data, encoding: .utf8) else { return }
        executor.execute(.pluginAction(pluginId: "random-passwd", actionId: "generate", payload: text))
    }

    private func requestLengthFocus() {
        Task { @MainActor in
            await Task.yield()
            focusedField = .length
        }
    }

    private func moveFocus(backward: Bool) {
        let fields: [Field] = [.length, .letters, .numbers, .symbols, .generate]
        let currentIndex = focusedField.flatMap { fields.firstIndex(of: $0) } ?? 0
        let offset = backward ? -1 : 1
        focusedField = fields[(currentIndex + offset + fields.count) % fields.count]
    }

    private static func parseInitialArguments(_ raw: String) -> Payload {
        var result = Payload(length: 20, letters: true, numbers: true, symbols: true)
        for token in raw.split(whereSeparator: { $0.isWhitespace }).map(String.init) {
            let lower = token.lowercased()
            if let length = Int(lower) {
                result = Payload(length: length, letters: result.letters, numbers: result.numbers, symbols: result.symbols)
                continue
            }
            let pair = lower.split(separator: "=", maxSplits: 1).map(String.init)
            if pair.count == 2, ["length", "len", "长度"].contains(pair[0]), let length = Int(pair[1]) {
                result = Payload(length: length, letters: result.letters, numbers: result.numbers, symbols: result.symbols)
            } else if ["no-letters", "无字母"].contains(lower) || pair == ["letters", "off"] {
                result = Payload(length: result.length, letters: false, numbers: result.numbers, symbols: result.symbols)
            } else if ["no-numbers", "no-digits", "无数字"].contains(lower) || pair == ["numbers", "off"] {
                result = Payload(length: result.length, letters: result.letters, numbers: false, symbols: result.symbols)
            } else if ["no-symbols", "无符号"].contains(lower) || pair == ["symbols", "off"] {
                result = Payload(length: result.length, letters: result.letters, numbers: result.numbers, symbols: false)
            }
        }
        return result
    }
}

/// SwiftUI TextField 会先于 onKeyPress 消费 Tab；局部 AppKit monitor 保证焦点不会逃出 nonactivating panel。
private struct FormTabKeyMonitor: NSViewRepresentable {
    let onTab: (Bool) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.install()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onTab = onTab
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.uninstall()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onTab: onTab) }

    final class Coordinator {
        var onTab: (Bool) -> Void
        private var monitor: Any?

        init(onTab: @escaping (Bool) -> Void) {
            self.onTab = onTab
        }

        func install() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard event.keyCode == 48 else { return event }
                self?.onTab(event.modifierFlags.contains(.shift))
                return nil
            }
        }

        func uninstall() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }
    }
}
