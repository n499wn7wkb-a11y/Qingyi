import AppKit
import SwiftUI
import Combine
import WebKit
import TranslationCore

// Use the property-wrapper type explicitly; newer SDKs also export a State macro.
private typealias ViewState<Value> = SwiftUI.State<Value>

private let translationBlue = Color(.sRGB, red: 0, green: 114.0 / 255.0, blue: 254.0 / 255.0, opacity: 1)

private struct ToolbarLabel: View {
    let systemImage: String
    var body: some View {
        Image(systemName: systemImage).font(.system(size: 16))
            .contentTransition(.symbolEffect(.replace))
            .animation(.easeInOut(duration: 0.2), value: systemImage)
            .frame(width: 28, height: 28)
            .contentShape(Rectangle())
    }
}

private struct ToolbarHoverStyle: ButtonStyle {
    var menuOpen = false
    @ViewState private var hovering = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .background {
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color.primary.opacity(isEnabled && configuration.isPressed ? 0.15 : (isEnabled && (hovering || menuOpen) ? 0.08 : 0)))
            }
            .onHover { hovering = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.1), value: hovering)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct TranslationView: View {
    @ObservedObject var model: AppModel
    let settings: () -> Void
    let close: () -> Void
    /// Where the pointer tail sits, and its centre along that edge. Passed in by
    /// the panel placement so the tail always aims at the selected text.
    var tail: BubbleTail = .none
    var tailOffset: CGFloat = 0
    @ViewState<Bool> private var copied = false
    @ViewState<Bool> private var originalExpanded = false
    @ViewState<Bool> private var sideBySide = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(model.source == "auto" ? model.detectedSource.map { Language.name(for: $0) + " · 自动检测" } ?? "自动检测" : Language.name(for: model.source))
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(Color.primary.opacity(0.72))
                Spacer()
                Button(action: settings) { ToolbarLabel(systemImage: "gearshape") }
                    .buttonStyle(ToolbarHoverStyle()).foregroundStyle(.primary).help("设置").accessibilityLabel("设置")
            }.padding(.bottom, 6)
            if !sideBySide { HStack(alignment: .top, spacing: 6) {
                if originalExpanded {
                    ScrollView {
                        Text(model.input.isEmpty ? "选中文字后翻译" : model.input)
                            .font(.system(size: 14)).foregroundStyle(.primary).lineSpacing(3)
                            .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                    }.frame(height: 85)
                } else {
                    Text(model.input.isEmpty ? "选中文字后翻译" : model.input)
                        .font(.system(size: 14)).foregroundStyle(.primary).lineSpacing(3)
                        .lineLimit(2).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                }
                Button { originalExpanded.toggle() } label: {
                    Image(systemName: originalExpanded ? "chevron.up" : "chevron.down").font(.system(size: 12))
                }.buttonStyle(.plain).foregroundStyle(.primary)
                    .help(originalExpanded ? "收起原文" : "展开原文")
                    .accessibilityLabel(originalExpanded ? "收起原文" : "展开原文")
            }.frame(maxHeight: originalExpanded ? 85 : 44, alignment: .top) }
            Divider().padding(.vertical, 12)
            HStack {
                Text(sideBySide ? "原文 / \(Language.name(for: model.target))" : Language.name(for: model.target)).font(.system(size: 13, weight: .medium)).foregroundStyle(Color.primary.opacity(0.72))
                Spacer()
                if model.busy { ProgressView().controlSize(.small) }
            }.padding(.bottom, 7)
            HStack(alignment: .top, spacing: 10) {
            if sideBySide {
                ScrollView { Text(model.input).font(.system(size: 14)).foregroundStyle(.primary).lineSpacing(3).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                Divider()
            }
            ScrollView {
                if let error = model.error {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(error).font(.system(size: 13)).foregroundStyle(.primary).fixedSize(horizontal: false, vertical: true)
                        if !AXIsProcessTrusted() && model.input.isEmpty { Button("打开设置", action: settings).buttonStyle(.bordered) }
                        else if !model.input.isEmpty { Button("重试") { model.translate(forceRefresh: true) }.buttonStyle(.bordered) }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                } else if model.busy && !model.previewOutput.isEmpty {
                    Text(model.previewOutput).font(.system(size: 18, weight: .medium)).foregroundStyle(translationBlue)
                        .lineSpacing(5).frame(maxWidth: .infinity, alignment: .leading)
                } else if model.busy {
                    Text("正在翻译…").font(.system(size: 16)).foregroundStyle(.tertiary).frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text(model.output).font(.system(size: 18, weight: .medium)).foregroundStyle(translationBlue)
                        .lineSpacing(5).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .clipped()
                .contentShape(Rectangle())
            }
            .clipped()
            if model.provider == .google {
                    Link(destination: URL(string: "https://translate.google.com")!) {
                        if let url = Bundle.main.url(forResource: colorScheme == .dark ? "GoogleTranslateWhite" : "GoogleTranslate", withExtension: "png"), let image = NSImage(contentsOf: url) {
                            Image(nsImage: image).resizable().interpolation(.high).frame(width: 154, height: 14)
                        } else { Text("Powered by Google Translate").font(.system(size: 10)) }
                    }.help("机器翻译由 Google Translate 提供").padding(.top, 4)
            }
            HStack {
                ProviderMenuButton(model: model).frame(width: 28, height: 28)
                Button { sideBySide.toggle() } label: { ToolbarLabel(systemImage: "rectangle.split.2x1") }
                    .buttonStyle(ToolbarHoverStyle()).foregroundStyle(sideBySide ? translationBlue : Color.primary)
                    .help(sideBySide ? "切换上下显示" : "左右对照")
                    .accessibilityLabel(sideBySide ? "切换上下显示" : "左右对照")
                if model.notesEnabled {
                    Button { model.archiveTranslation() } label: { ToolbarLabel(systemImage: model.archiveSaved ? "checkmark" : "archivebox") }
                        .buttonStyle(ToolbarHoverStyle()).foregroundStyle(.primary)
                        .disabled(model.input.isEmpty || model.output.isEmpty || model.busy || model.archiveBusy)
                        .help(model.archiveSaved ? "已保存" : "存入备忘录").accessibilityLabel(model.archiveSaved ? "已保存到备忘录" : "存入备忘录")
                }
                Spacer()
                Button {
                    NSPasteboard.general.clearContents(); NSPasteboard.general.setString(model.output, forType: .string); copied = true
                } label: { ToolbarLabel(systemImage: copied ? "checkmark" : "doc.on.doc") }
                    .buttonStyle(ToolbarHoverStyle()).foregroundStyle(.primary).disabled(model.output.isEmpty)
                    .help(copied ? "已复制" : "复制译文").accessibilityLabel(copied ? "已复制" : "复制译文")
            }
            .overlay {
                HStack(spacing: 5) {
                    if model.archiveBusy {
                        ProgressView().controlSize(.mini)
                        Text("正在存档…").foregroundStyle(.secondary)
                    } else if let message = model.archiveMessage {
                        Text(message).foregroundStyle(message == "存档失败" ? Color.red : Color.secondary)
                    }
                }
                .font(.system(size: 11)).lineLimit(1)
                .offset(y: 1.5)
                .accessibilityElement(children: .combine).allowsHitTesting(false)
            }
            .padding(.top, 4).zIndex(1)
        }
        .padding(20)
        .frame(width: 360, height: 345)
        .popupGlass(tail: tail, tailOffset: tailOffset)
        .background {
            if model.provider == .google, model.webURL != nil {
                GooglePageHost(session: model.googlePageSession)
                    .frame(width: 840, height: 620)
                    .scaleEffect(0.001, anchor: .topLeading)
                    .frame(width: 1, height: 1, alignment: .topLeading)
                    .opacity(0.01).allowsHitTesting(false).accessibilityHidden(true)
            }
        }
        .onDisappear { model.providerMenuPresented = false }
        .onChange(of: model.output) { _, _ in copied = false }
        .onChange(of: model.input) { _, _ in originalExpanded = false }
        .onExitCommand(perform: close)
    }
}

// Google Translate's consumer website runs in a tiny background view; the user sees only the native result.
// The website's DOM is undocumented and can change. Only show text after confirming Advanced is selected.
private struct DragonIcon: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ViewState private var dragonX: CGFloat = 0
    @ViewState private var chickenX: CGFloat = 0
    @ViewState private var dragonY: CGFloat = 13
    @ViewState private var chickenY: CGFloat = 13
    @ViewState private var dragonOpacity = 0.0
    @ViewState private var chickenOpacity = 0.0
    @ViewState private var playing = false
    @ViewState private var presses = 0
    @ViewState private var lastPress = Date.distantPast
    @ViewState private var run: Task<Void, Never>?

    var body: some View {
        ZStack {
            ZStack {
                if let url = Bundle.main.url(forResource: "Dragon", withExtension: "png"), let image = NSImage(contentsOf: url) {
                    Image(nsImage: image).resizable().interpolation(.none).scaledToFit()
                        .frame(width: 48, height: 43).offset(x: dragonX, y: dragonY).opacity(dragonOpacity)
                }
                if let url = Bundle.main.url(forResource: "Chick", withExtension: "png"), let image = NSImage(contentsOf: url) {
                    Image(nsImage: image).resizable().interpolation(.none).scaledToFit().scaleEffect(x: -1, y: 1)
                        .frame(width: 43, height: 43).offset(x: chickenX, y: chickenY).opacity(chickenOpacity)
                }
            }.frame(width: 110, height: 80).clipped().offset(y: -13)
                .opacity(playing ? 1 : 0).allowsHitTesting(false).accessibilityHidden(true)
            Button(action: tap) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable().interpolation(.high).scaledToFit().frame(width: 54, height: 54)
            }.buttonStyle(DragonPressStyle()).accessibilityLabel("轻译图标")
        }.frame(width: 54, height: 54)
            .onDisappear { run?.cancel(); run = nil; playing = false; dragonX = 0; chickenX = 0; dragonY = 13; chickenY = 13; dragonOpacity = 0; chickenOpacity = 0 }
    }
    private func tap() {
        guard !playing else { return }
        let now = Date()
        presses = now.timeIntervalSince(lastPress) < 1.8 ? presses + 1 : 1
        lastPress = now
        if presses >= 5 { presses = 0; play() }
    }
    private func play() {
        guard !playing else { return }; playing = true
        run = Task { @MainActor in
            if reduceMotion {
                dragonX = -14; chickenX = 14; dragonY = -13; chickenY = -13; dragonOpacity = 1; chickenOpacity = 1
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            } else {
                withAnimation(.easeOut(duration: 0.8)) { dragonX = -15; dragonY = -13; dragonOpacity = 1 }
                try? await Task.sleep(nanoseconds: 600_000_000); guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.8)) { chickenX = 15; chickenY = -13; chickenOpacity = 1 }
                try? await Task.sleep(nanoseconds: 900_000_000); guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 0.5)) { dragonX = -9; chickenX = 9; dragonY = -15; chickenY = -15 }
                try? await Task.sleep(nanoseconds: 550_000_000); guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 0.5)) { dragonX = -15; chickenX = 15; dragonY = -13; chickenY = -13 }
                try? await Task.sleep(nanoseconds: 1_000_000_000); guard !Task.isCancelled else { return }
            }
            guard !Task.isCancelled else { return }
            withAnimation(reduceMotion ? nil : .easeIn(duration: 0.7)) { dragonX = 0; chickenX = 0; dragonY = 13; chickenY = 13; dragonOpacity = 0; chickenOpacity = 0 }
            try? await Task.sleep(nanoseconds: 750_000_000)
            guard !Task.isCancelled else { return }; playing = false
        }
    }
}
private struct DragonPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed ? 0.93 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ViewState<Bool> private var accessibility = AXIsProcessTrusted()
    @ViewState<Bool> private var advancedSettings = false
    @ViewState<Bool> private var choosingNotesFolder = false
    @ViewState<String> private var selectedNotesFolder = ""
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 12) {
                    DragonIcon()
                    VStack(alignment: .leading, spacing: 4) {
                        Text("轻译").font(.system(size: 24, weight: .semibold))
                        Text("选中，按一下，读译文。").font(.system(size: 13)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—").font(.caption).foregroundStyle(.tertiary)
                }.padding(.bottom, 2)

                Picker("设置分类", selection: $advancedSettings) {
                    Label("通用", systemImage: "slider.horizontal.3").tag(false)
                    Label("高级", systemImage: "gearshape.2").tag(true)
                }.pickerStyle(.segmented).labelsHidden()
                if !advancedSettings {
                VStack(spacing: 17) {
                    HStack {
                        Text("原文语言").font(.system(size: 13))
                        Spacer()
                        Picker("原文语言", selection: $model.source) {
                            Text("自动检测").tag("auto")
                            ForEach(Language.targets) { language in Text(language.name).tag(language.id) }
                        }.labelsHidden().frame(width: 160)
                    }
                    Divider()
                    HStack {
                        Text("译成").font(.system(size: 13))
                        Spacer()
                        Picker("目标语言", selection: $model.target) {
                            ForEach(Language.targets) { language in Text(language.name).tag(language.id) }
                        }.labelsHidden().frame(width: 160)
                    }
                }.card()
                VStack(alignment: .leading, spacing: 10) {
                    Text("翻译要求").font(.system(size: 14, weight: .semibold))
                    Text("仅用于 AI 接口，自动保存。例如：中文表达自然流畅，保留原文语气。")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    TextEditor(text: $model.translationPreferences).font(.system(size: 13)).frame(height: 72)
                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.secondary.opacity(0.25)))
                }.card()
                VStack(alignment: .leading, spacing: 12) {
                    Text("翻译服务").font(.system(size: 14, weight: .semibold))
                    Picker("翻译服务", selection: $model.provider) {
                        ForEach(TranslationProvider.allCases) { provider in Text(provider.title).tag(provider) }
                    }.labelsHidden().onChange(of: model.provider) { _, _ in model.loadProviderSettings() }
                    if model.provider != .google {
                        TextField("模型名称", text: $model.modelName)
                            .textFieldStyle(.roundedBorder)
                        if model.provider == .deepSeek {
                            Toggle("深度思考", isOn: $model.deepSeekThinking)
                            Text("适合较复杂的文本；可能需要更多时间和费用。")
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        if model.provider == .custom {
                            TextField("接口地址，例如 https://example.com/v1", text: $model.endpoint)
                                .textFieldStyle(.roundedBorder)
                        }
                        SecureField("API Key", text: $model.apiKey).textFieldStyle(.roundedBorder)
                        HStack {
                            Button("保存") { _ = model.saveProviderSettings() }.disabled(model.keyLoading)
                            Button("测试连接") { model.testConnection() }.disabled(model.testingConnection || model.keyLoading)
                            if model.testingConnection { ProgressView().controlSize(.small) }
                        }
                        if let message = model.connectionMessage {
                            Text(message).font(.system(size: 11)).foregroundStyle(.primary).fixedSize(horizontal: false, vertical: true)
                        }
                        Text("密钥保存在钥匙串中。接口可能按用量收费。")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    } else {
                        Text("无需 API Key。Google 翻译网页会在后台处理文字，高级模式由 Google 提供。")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }.card()
                } else {
                Text("高级设置").font(.system(size: 20, weight: .semibold))
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("划词快捷键").font(.system(size: 13))
                        Spacer()
                        Button(model.shortcut.title) {
                            model.hotkeyWarning = nil
                            model.recordingShortcut = true
                        }.buttonStyle(.bordered).frame(minWidth: 110)
                            .accessibilityLabel("录入划词快捷键，当前为 \(model.shortcut.title)")
                        Button("重设") { _ = model.applyShortcut(.controlOptionT) }
                            .buttonStyle(.borderless).help("恢复默认快捷键 ⌃⌥T")
                    }
                    if let warning = model.hotkeyWarning {
                        Text(warning).font(.system(size: 12)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                    }
                }.card()
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("保存到备忘录", isOn: $model.notesEnabled)
                        .font(.system(size: 14, weight: .semibold))
                        .onChange(of: model.notesEnabled) { _, enabled in
                            if enabled && model.notesFolderID.isEmpty { selectedNotesFolder = ""; choosingNotesFolder = true; model.loadNotesFolders() }
                        }
                    Text("每天保存到一篇以日期命名的笔记，原文和译文一起存档。")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    HStack {
                        Text(model.notesFolderPath.isEmpty ? "尚未选择存储位置" : "存储位置：\(model.notesFolderPath)")
                            .font(.system(size: 11)).foregroundStyle(.primary).lineLimit(2)
                        Spacer()
                        Button("更改…") { selectedNotesFolder = model.notesFolderID; choosingNotesFolder = true; model.loadNotesFolders() }
                            .disabled(!model.notesEnabled)
                    }
                }.card()
                VStack(alignment: .leading, spacing: 12) {
                    Text("Google 翻译高级模式").font(.system(size: 14, weight: .semibold))
                    Text("后台翻译页面保留时间").font(.system(size: 13))
                    Picker("后台翻译页面保留时间", selection: $model.googlePageRetention) {
                        ForEach(GooglePageRetention.allCases) { option in Text(option.title).tag(option) }
                    }.labelsHidden().frame(maxWidth: .infinity, alignment: .leading)
                    Text("保留已加载的页面，可减少下一次翻译的等待；保留期间会持续占用部分内存。")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    Text(model.googlePageRetention == .untilQuit ? "页面会一直保留，直到你退出轻译。" : "翻译完成且弹窗关闭后开始计时；再次翻译时重新计时。释放后，下次使用会重新加载。")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    Text("仅在首次使用 Google 翻译时加载，不影响其他 API 翻译服务。")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }.card()
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("辅助功能权限").font(.system(size: 14, weight: .semibold))
                        Spacer()
                        Label(accessibility ? "已开启" : "未开启", systemImage: accessibility ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 11)).foregroundStyle(accessibility ? .green : .secondary)
                    }
                    Text("用于读取你主动选中的文字。授权后，在其他应用中选中文字，按 \(model.shortcut.title)。")
                        .font(.system(size: 12)).foregroundStyle(.primary).lineSpacing(4)
                    if !accessibility {
                        Button("前往系统设置授权") {
                            SystemCapture.requestAccessibility()
                            SystemCapture.openAccessibilitySettings()
                        }.buttonStyle(.bordered)
                    }
                }.card()
                }
                Text(model.provider == .google ? "所选文字会发送给 Google，并包含在后台网页地址中。" : "所选文字会发送给你选择的 API 服务商。")
                    .font(.system(size: 11)).foregroundStyle(.primary).lineSpacing(4)
                HStack {
                    Button("关于翻译") {
                        let alert = NSAlert()
                        alert.messageText = "Google Translate 机器翻译"
                        alert.informativeText = "THIS SERVICE MAY CONTAIN TRANSLATIONS POWERED BY GOOGLE. GOOGLE DISCLAIMS ALL WARRANTIES RELATED TO THE TRANSLATIONS, EXPRESS OR IMPLIED, INCLUDING ANY WARRANTIES OF ACCURACY, RELIABILITY, AND ANY IMPLIED WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT."
                        alert.addButton(withTitle: "好")
                        alert.runModal()
                    }.buttonStyle(.link)
                }.font(.system(size: 11))
            }
            .padding(.top, 18)
            .padding(26)
        }
        // Only the actual titlebar is frosted; the icon and Easter egg keep
        // their original scrolling layout and have no separate edge overlay.
        .overlay(alignment: .top) {
            Rectangle().fill(.ultraThinMaterial).frame(height: 28)
                .mask(LinearGradient(stops: [
                    .init(color: .black, location: 0),
                    .init(color: .black, location: 0.78),
                    .init(color: .clear, location: 1)
                ], startPoint: .top, endPoint: .bottom))
                .allowsHitTesting(false).accessibilityHidden(true)
        }
        // Order matters. The glass has to be applied to the outermost view first
        // and the content inset afterwards; padding before the background leaves
        // the padded strip outside the glass, which is exactly the bare band that
        // showed up behind the traffic lights.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .settingsSurface()
        // Ignore the window's safe area: with `.fullSizeContentView` the titlebar
        // insets the content by its own height, pushing it down.
        .ignoresSafeArea()
            .sheet(isPresented: $model.recordingShortcut) {
                ShortcutEditor(model: model)
            }
            .sheet(isPresented: $choosingNotesFolder) {
                VStack(alignment: .leading, spacing: 16) {
                    Text("选择备忘录文件夹").font(.headline)
                    Text("选择一次后，轻译会将每天的摘录保存到这里。")
                        .font(.caption).foregroundStyle(.primary)
                    if model.notesLoading { ProgressView("正在读取文件夹…") }
                    else if let message = model.notesMessage { Text(message).font(.caption).foregroundStyle(.primary) }
                    else {
                        Picker("存储位置", selection: $selectedNotesFolder) {
                            Text("请选择文件夹").tag("")
                            ForEach(model.notesFolders) { folder in Text(folder.path).tag(folder.id) }
                        }.frame(width: 350)
                    }
                    HStack {
                        Spacer()
                        Button("取消") { choosingNotesFolder = false }
                        Button("选择") {
                            if let folder = model.notesFolders.first(where: { $0.id == selectedNotesFolder }) {
                                model.notesFolderID = folder.id; model.notesFolderPath = folder.path
                            }
                            choosingNotesFolder = false
                        }.disabled(!model.notesFolders.contains(where: { $0.id == selectedNotesFolder }))
                    }
                }.padding(24).frame(width: 410)
            }
            .onAppear { accessibility = AXIsProcessTrusted() }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                accessibility = AXIsProcessTrusted()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { notification in
                if (notification.object as? NSWindow)?.title == "轻译设置" { accessibility = AXIsProcessTrusted() }
            }
    }
}

private extension View {
    /// Match the settings window using the same regular glass material.
    func popupGlass(tail: BubbleTail = .none, tailOffset: CGFloat = 0) -> some View {
        let shape = BubbleShape(cornerRadius: 24, tail: tail, tailOffset: tailOffset)
        let inset = shape.tailInsets
        return self
            .padding(EdgeInsets(top: inset.top, leading: inset.left,
                                bottom: inset.bottom, trailing: inset.right))
            .background { Color.clear.glassEffect(.regular, in: shape) }
            .background { shape.fill(Color.black.opacity(0.001)).contentShape(shape) }
            // Clip content to the glass shape. Without this the bottom toolbar
            // and scroll content paint into the square corners outside the
            // rounded curve, leaving a pale rectangular smudge against the
            // desktop. Also kill the compositing group so no intermediate layer
            // paints outside the shape.
            .compositingGroup()
            .clipShape(shape)
            // A hairline border replaces the edge contrast `.regular` used to get
            // from its own darkening. 9% black is the smallest amount that still
            // reads as an edge against white paper without looking like a frame.
            .overlay { shape.stroke(Color.black.opacity(0.09), lineWidth: 0.75).allowsHitTesting(false) }
            // Keyboard focus in this panel is an implementation detail, not
            // something the user navigates, so no focus ring is wanted. Without
            // this the ring draws a hard rectangular outline across the rounded
            // corners.
            //
            // The drop shadow is deliberately NOT drawn here: glass is
            // translucent, so a shadow composited behind it gets sampled by the
            // glass and turns the whole popup grey. The popup window also has
            // its native shadow disabled in AppDelegate.
            .focusEffectDisabled()
    }
    /// Root surface of the settings window. The window itself is transparent
    /// (`isOpaque = false`, `backgroundColor = .clear`), so this is the only
    /// thing the user sees — and it has to be glass, not a material: a material
    /// here sits between the glass and the desktop and flattens it to grey.
    func settingsSurface() -> some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return self
            .background { Color.clear.glassEffect(.regular, in: shape) }
            // Clip to the same shape the glass uses. Without this the scroll
            // content paints past the rounded corners and shows through the
            // desktop outside the window's curve.
            .clipShape(shape)
    }
    func glassSurface(radius: CGFloat) -> some View {
        self.background {
            Color.clear.glassEffect(.regular, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
        }
    }
    func interactiveGlassCircle() -> some View {
        self.background { Color.clear.glassEffect(.regular.interactive(), in: Circle()) }
    }
    func glassButton() -> some View {
        self.buttonStyle(.glass)
    }
    func card() -> some View { self.padding(18).glassSurface(radius: 20) }
}
