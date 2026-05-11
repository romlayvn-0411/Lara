//
//  ContentView.swift
//  lara
//
//  Created by ruter on 23.03.26.
//

import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var mgr: laramgr
    @ObservedObject private var logger = globallogger
    @AppStorage("selectedMethod") private var selectedmethod: method = .hybrid
    @AppStorage("logsdisplaymode") private var selectedlogsdisplaymode: logsdisplaymode = .toolbar
    @AppStorage("loggerNoBS") private var loggernobs: Bool = true
    
    @State private var showSettings: Bool = false
    
    init() {
        globallogger.capture()
    }
    
    var body: some View {
        NavigationStack {
            List {
                AlertsSection
                KRWSection
                RCSection
                ActionsSection
                DebugSection
                InlineLogsSection
            }
            .navigationTitle("lara")
            .toolbar {
                if selectedlogsdisplaymode == .toolbar {
                    Button(action: {
                        mgr.showLogs.toggle()
                    }) {
                        Image(systemName: "terminal")
                    }
                }
                Button(action: {
                    showSettings.toggle()
                }) {
                    Image(systemName: "gear")
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
        }
    }
    
    private var AlertsSection: some View {
        Section {
            if !mgr.hasOffsets {
                PlainAlert(title: "No offsets found!", icon: "exclamationmark.triangle.fill", text: "Kernelcache offsets are missing. Go download them in settings.")
                Button("Open Settings", action: {
                    showSettings.toggle()
                })
            }
        }
    }
    
    private var KRWSection: some View {
        Section {
            // run exploit
            LabeledContent(content: {
                if mgr.dsready {
                    Image(systemName: "checkmark.circle")
                } else if mgr.dsrunning {
                    HStack {
                        Text("\(Int(mgr.dsprogress * 100))%")
                        ProgressView()
                    }
                } else if mgr.dsattempted && mgr.dsfailed {
                    Image(systemName: "xmark.circle")
                }
            }) {
                Button("Run Exploit", action: {
                    offsets_init()
                    mgr.run()
                })
                .disabled(!mgr.hasOffsets || mgr.dsready || mgr.dsrunning || isdebugged())
            }
            
            // hybrid button
            if selectedmethod == .hybrid {
                LabeledContent(content: {
                    if mgr.vfsready && mgr.sbxready {
                        Image(systemName: "checkmark.circle")
                    } else if mgr.vfsrunning || mgr.sbxrunning {
                        HStack {
                            Text("Running...")
                            ProgressView()
                        }
                    } else if (mgr.vfsattempted && mgr.vfsfailed) || (mgr.sbxattempted && mgr.sbxfailed) {
                        Image(systemName: "xmark.circle")
                    }
                }) {
                    Button("Initialize System", action: {
                        mgr.vfsinit()
                        mgr.sbxescape()
                    })
                    .disabled(!mgr.dsready || mgr.vfsrunning || mgr.sbxrunning || (mgr.vfsready && mgr.sbxready))
                }
            }
            
            // initalize vfs
            if selectedmethod == .vfs {
                LabeledContent(content: {
                    if mgr.vfsready {
                        Image(systemName: "checkmark.circle")
                    } else if mgr.vfsrunning {
                        HStack {
                            Text("\(Int(mgr.dsprogress * 100))%")
                            ProgressView()
                        }
                    } else if mgr.vfsattempted && mgr.vfsfailed {
                        Image(systemName: "xmark.circle")
                    }
                }) {
                    Button("Initialize VFS", action: {
                        mgr.vfsinit()
                    })
                    .disabled(!mgr.dsready || mgr.vfsready || mgr.vfsrunning || isdebugged())
                }
            }
            
            // escape sandbox
            if selectedmethod == .sbx {
                LabeledContent(content: {
                    if mgr.sbxready {
                        Image(systemName: "checkmark.circle")
                    } else if mgr.sbxrunning {
                        HStack {
                            Text("Running...")
                            ProgressView()
                        }
                    } else if mgr.sbxattempted && mgr.sbxfailed {
                        Image(systemName: "xmark.circle")
                    }
                }) {
                    Button("Escape Sandbox", action: {
                        mgr.sbxescape()
                    })
                    .disabled(!mgr.dsready || mgr.sbxready || mgr.sbxrunning || isdebugged())
                }
            }
        } header: {
            HeaderLabel(text: "Kernel Read Write", icon: "externaldrive")
        } footer: {
            if isdebugged() {
                Text("Not available while a debugger is attached.")
            }
        }
    }
    
    private var RCSection: some View {
        Group {
            #if !DISABLE_REMOTECALL
            Section {
                // init remotecall
                LabeledContent(content: {
                    if mgr.rcready {
                        Image(systemName: "checkmark.circle")
                    } else if mgr.rcrunning {
                        HStack {
                            Text("Running...")
                            ProgressView()
                        }
                    } else if mgr.rcfailed {
                        Image(systemName: "xmark.circle")
                    }
                }) {
                    Button("Initalize RemoteCall", action: {
                        mgr.rcinit(process: "SpringBoard", migbypass: false) { success in
                            if success {
                                mgr.logmsg("rc init succeeded!")
                                let pid = mgr.rccall(name: "getpid")
                                mgr.logmsg("remote getpid() returned: \(pid)")
                            } else {
                                mgr.logmsg("rc init failed")
                                mgr.rcfailed = true
                            }
                        }
                    })
                    .disabled(!mgr.dsready || isdebugged() || mgr.rcrunning || mgr.rcready)
                }
                
                // destroy remotecall
                if mgr.rcready {
                    Button("Destroy Remotecall", action: {
                        mgr.rcdestroy()
                    })
                }
            } header: {
                HeaderLabel(text: "RemoteCall", icon: "syringe")
            } footer: {
                if let error = mgr.rcLastError ?? mgr.sbProc?.lastError {
                    Text("Error: \(error)")
                        .foregroundColor(.red)
                }
                if RemoteCall.isLiveContainerRuntime() && !RemoteCall.isLiveProcessRuntime() {
                    Text("RemoteCall needs a PAC-enabled LiveContainer launch context. The main exploit may still work when RemoteCall is unavailable.")
                }
                if isdebugged() {
                    Text("Not available when a debugger is attached.")
                }
                Text("RemoteCall is relatively unstable and may not work properly.")
            }
            #endif
        }
    }
    
    private var ActionsSection: some View {
        Section(header: HeaderLabel(text: "Actions", icon: "wrench.and.screwdriver")) {
            Button("Respring", action: {
                mgr.respring()
            })
            
            Button("Panic!", action: {
                mgr.panic()
            })
            
            if isdebugged() {
                Button("Detach Debugger", action: {
                    exit(0)
                })
            }
        }
    }
    
    private var DebugSection: some View {
        Group {
            if weonadebugbuild_pjbweouttahereexclamationmark {
                if mgr.dsready {
                    Section(header: HeaderLabel(text: "Debug Only", icon: "ant")) {
                        LabeledContent("kernel_base") {
                            Text(String(format: "0x%llx", mgr.kernbase))
                                .font(.system(.body, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                        LabeledContent("kernel_slide") {
                            Text(String(format: "0x%llx", mgr.kernslide))
                                .font(.system(.body, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var InlineLogsSection: some View {
        if selectedlogsdisplaymode == .content {
            Section {
                ScrollView {
                    if loggernobs {
                        let combined = logger.logs.joined(separator: "\n")
                        Text(combined)
                            .font(.system(size: 13, design: .monospaced))
                            .lineSpacing(1)
                            .textSelection(.enabled)
                            .onTapGesture {
                                UIPasteboard.general.string = combined
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            }
                    } else {
                        ForEach(Array(logger.logs.enumerated()), id: \.offset) { _, log in
                            Text(log)
                                .font(.system(size: 13, design: .monospaced))
                                .lineSpacing(1)
                                .textSelection(.enabled)
                                .onTapGesture {
                                    UIPasteboard.general.string = log
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                }
                        }
                    }
                }
                .frame(height: 250)
                
                Button("Copy All") {
                    UIPasteboard.general.string = logger.logs.joined(separator: "\n\n")
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                }
                
                Button("Clear") {
                    logger.clear()
                }
                .foregroundColor(.red)
            } header: {
                HeaderLabel(text: "Logs", icon: "terminal")
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(laramgr())
}

struct FortFaggotView: View {
    @AppStorage("showfmintabs") private var showfmintabs: Bool = true
    @ObservedObject private var mgr = laramgr.shared
    @Binding var hasoffsets: Bool
    @State private var showsettings = false
    @State private var selectedmethod: method = .hybrid

    let os = ProcessInfo().operatingSystemVersion

    var body: some View {
        NavigationStack {
            List {
                if !hasoffsets {
                    Section("Setup") {
                        Text("Kernelcache offsets are missing. Download them in Settings.")
                            .foregroundColor(.secondary)
                        Button("Open Settings") {
                            showsettings = true
                        }
                    }
                } else {
                    Section {
                        Button {
                            offsets_init()
                            mgr.run()
                        } label: {
                            if mgr.dsrunning {
                                HStack {
                                    ProgressView(value: mgr.dsprogress)
                                        .progressViewStyle(.circular)
                                        .frame(width: 18, height: 18)
                                    Text("Running...")
                                    Spacer()
                                    Text("\(Int(mgr.dsprogress * 100))%")
                                }
                            } else {
                                if mgr.dsready {
                                    HStack {
                                        Text("Ran Exploit")
                                        Spacer()
                                        Image(systemName: "checkmark.circle")
                                            .foregroundColor(.green)
                                    }
                                } else if mgr.dsattempted && mgr.dsfailed {
                                    HStack {
                                        Text("Exploit Failed")
                                        Spacer()
                                        Image(systemName: "xmark.circle")
                                            .foregroundColor(.red)
                                    }
                                } else {
                                    Text("Run Exploit")
                                }
                            }
                        }
                        .disabled(mgr.dsrunning)
                        .disabled(mgr.dsready)
                        .disabled(isdebugged())

                        if mgr.dsready {
                            HStack {
                                Text("kernel_base:")
                                Spacer()
                                Text(String(format: "0x%llx", mgr.kernbase))
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }

                            HStack {
                                Text("kernel_slide:")
                                Spacer()
                                Text(String(format: "0x%llx", mgr.kernslide))
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        if isdebugged() {
                            Button {
                                exit(0)
                            } label: {
                                Text("Detach")
                            }
                            .foregroundColor(.red)
                        }
                    } header: {
                        Text("Kernel Read Write")
                    } footer: {
                        if g_isunsupported {
                            Text("Your device/installation method may not be supported.")
                        }
                        
                        if isdebugged() {
                            Text("Not available while debugger is attached.")
                        }
                    }

                    Section {
                        if selectedmethod == .vfs {
                            Button {
                                mgr.vfsinit()
                            } label: {
                                if mgr.vfsrunning {
                                    HStack {
                                        ProgressView(value: mgr.vfsprogress)
                                            .progressViewStyle(.circular)
                                            .frame(width: 18, height: 18)
                                        Text("Initialising VFS...")
                                        Spacer()
                                        Text("\(Int(mgr.vfsprogress * 100))%")
                                    }
                                } else if !mgr.vfsready {
                                    if mgr.vfsattempted && mgr.vfsfailed {
                                        HStack {
                                            Text("VFS Init Failed")
                                            Spacer()
                                            Image(systemName: "xmark.circle")
                                                .foregroundColor(.red)
                                        }
                                    } else {
                                        Text("Initialise VFS")
                                    }
                                } else {
                                    HStack {
                                        Text("Initialised VFS")
                                        Spacer()
                                        Image(systemName: "checkmark.circle")
                                            .foregroundColor(.green)
                                    }
                                }
                            }
                            .disabled(!mgr.dsready || mgr.vfsready || mgr.vfsrunning)

                            if mgr.vfsready {
                                NavigationLink("Tweaks") {
                                    List {
                                        Section {
                                            NavigationLink {
                                                FontPicker(mgr: mgr)
                                            } label: {
                                                Label("Font Overwrite", systemImage: "textformat.alt")
                                            }

                                            NavigationLink {
                                                CardView()
                                            } label: {
                                                Label("Card Overwrite", systemImage: "creditcard")
                                            }

                                            NavigationLink {
                                                ZeroView(mgr: mgr)
                                            } label: {
                                                Label("DirtyZero", systemImage: "doc")
                                            }
                                        } header: {
                                            Text("UI Tweaks")
                                        }

                                        Section {
                                            if !showfmintabs {
                                                NavigationLink {
                                                    SantanderView(startPath: "/")
                                                } label: {
                                                    Label("File Manager", systemImage: "folder")
                                                }
                                            }
                                            
                                            NavigationLink {
                                                CustomView(mgr: mgr)
                                            } label: {
                                                Label("Custom Overwrite", systemImage: "pencil")
                                            }
                                        } header: {
                                            Text("Other")
                                        }
                                    }
                                    .navigationTitle(Text("Tweaks"))
                                }
                            }
                        } else if selectedmethod == .sbx {
                            Button {
                                mgr.sbxescape()
                                // mgr.sbxelevate()
                            } label: {
                                if mgr.sbxrunning {
                                    HStack {
                                        ProgressView()
                                            .progressViewStyle(.circular)
                                            .frame(width: 18, height: 18)
                                        Text("Escaping Sandbox...")
                                    }
                                } else if !mgr.sbxready {
                                    if mgr.sbxattempted && mgr.sbxfailed {
                                        HStack {
                                            Text("Sandbox Escape Failed")
                                            Spacer()
                                            Image(systemName: "xmark.circle")
                                                .foregroundColor(.red)
                                        }
                                    } else {
                                        Text("Escape Sandbox")
                                    }
                                } else {
                                    HStack {
                                        Text("Sandbox Escaped")
                                        Spacer()
                                        Image(systemName: "checkmark.circle")
                                            .foregroundColor(.green)
                                    }
                                }
                            }
                            .disabled(!mgr.dsready || mgr.sbxready || mgr.sbxrunning)

                            if mgr.sbxready {
                                NavigationLink("Tweaks") {
                                    List {
                                        Section {
                                            NavigationLink {
                                                CardView()
                                            } label: {
                                                Label("Card Overwrite", systemImage: "creditcard")
                                            }
                                        } header: {
                                            Text("UI Tweaks")
                                        }

                                        Section {
                                            NavigationLink {
                                                AppsView(mgr: mgr)
                                            } label: {
                                                Label("3 App Bypass", systemImage: "lock.open.fill")
                                            }

                                            NavigationLink {
                                                WhitelistView()
                                            } label: {
                                                Label("Unblacklist", systemImage: "checkmark.seal")
                                            }
                                        } header: {
                                            Text("App Management")
                                        }

                                        Section {
                                            if !showfmintabs {
                                                NavigationLink {
                                                    SantanderView(startPath: "/")
                                                } label: {
                                                    Label("File Manager", systemImage: "folder")
                                                }
                                            }
                                        } header: {
                                            Text("Filesystem")
                                        }

                                        Section {
                                            NavigationLink {
                                                VarCleanView()
                                            } label: {
                                                Label("VarClean", systemImage: "sparkles")
                                            }
                                        } header: {
                                            Text("Cleanup")
                                        }

                                        if 1 == 2 {
                                            NavigationLink {
                                                EditorView()
                                            } label: {
                                                Label("MobileGestalt", systemImage: "gear")
                                            }
                                            NavigationLink {
                                                PasscodeView(mgr: mgr)
                                            } label: {
                                                Label("Passcode Theme", systemImage: "1.circle")
                                            }
                                        }
                                    }
                                    .navigationTitle(Text("Tweaks"))
                                }
                            }
                        } else {
                            if !mgr.sbxattempted {
                                Button {
                                    mgr.sbxescape()
                                } label: {
                                    if mgr.sbxrunning {
                                        HStack {
                                            ProgressView()
                                                .progressViewStyle(.circular)
                                                .frame(width: 18, height: 18)
                                            Text("Escaping Sandbox...")
                                        }
                                    } else if !mgr.sbxready {
                                        if mgr.sbxattempted && mgr.sbxfailed {
                                            HStack {
                                                Text("Sandbox Escape Failed")
                                                Spacer()
                                                Image(systemName: "xmark.circle")
                                                    .foregroundColor(.red)
                                            }
                                        } else {
                                            Text("Escape Sandbox")
                                        }
                                    } else {
                                        HStack {
                                            Text("Sandbox Escaped")
                                            Spacer()
                                            Image(systemName: "checkmark.circle")
                                                .foregroundColor(.green)
                                        }
                                    }
                                }
                                .disabled(!mgr.dsready || mgr.sbxready || mgr.sbxrunning)
                            } else {
                                Button {
                                    mgr.vfsinit()
                                } label: {
                                    if mgr.vfsrunning {
                                        HStack {
                                            ProgressView(value: mgr.vfsprogress)
                                                .progressViewStyle(.circular)
                                                .frame(width: 18, height: 18)
                                            Text("Initialising VFS...")
                                            Spacer()
                                            Text("\(Int(mgr.vfsprogress * 100))%")
                                        }
                                    } else if !mgr.vfsready {
                                        if mgr.vfsattempted && mgr.vfsfailed {
                                            HStack {
                                                Text("VFS Init Failed")
                                                Spacer()
                                                Image(systemName: "xmark.circle")
                                                    .foregroundColor(.red)
                                            }
                                        } else {
                                            Text("Initialise VFS")
                                        }
                                    } else {
                                        HStack {
                                            Text("Initialised Hybrid")
                                            Spacer()
                                            Image(systemName: "checkmark.circle")
                                                .foregroundColor(.green)
                                        }
                                    }
                                }
                                .disabled(!mgr.dsready || mgr.vfsready || mgr.vfsrunning)
                            }

                            if mgr.vfsready && mgr.sbxready {
                                NavigationLink("Tweaks") {
                                    List {
                                        Section {
                                            NavigationLink {
                                                FontPicker(mgr: mgr)
                                            } label: {
                                                Label("Font Overwrite", systemImage: "textformat.alt")
                                            }

                                            NavigationLink {
                                                CardView()
                                            } label: {
                                                Label("Card Overwrite", systemImage: "creditcard")
                                            }

                                            NavigationLink {
                                                ZeroView(mgr: mgr)
                                            } label: {
                                                Label("DirtyZero", systemImage: "doc")
                                            }
                                            
                                            if 1 == 2 {
                                                NavigationLink {
                                                    DarkBoardView()
                                                } label: {
                                                    Label("DarkBoard", systemImage: "app.badge")
                                                }
                                            }
                                            
                                            if os.majorVersion >= 26 {
                                                NavigationLink {
                                                    LGView()
                                                } label: {
                                                    Label("Liquid Glass", systemImage: "capsule")
                                                }
                                            }
                                        } header: {
                                            Text("SpringBoard")
                                        }
                                        Section {
                                            NavigationLink() {
                                                PasscodeView(mgr: mgr)
                                            } label: {
                                                Label("Passcode Theme", systemImage: "key")
                                            }
                                        } header: {
                                            Text("Lockscreen")
                                        }
                                        Section {
                                            NavigationLink {
                                                AppsView(mgr: mgr)
                                            } label: {
                                                Label("3 App Bypass", systemImage: "lock.open.fill")
                                            }
                                            NavigationLink {
                                                WhitelistView()
                                            } label: {
                                                Label("Unblacklist", systemImage: "checkmark.seal")
                                            }
                                        } header: {
                                            Text("App Management")
                                        }
                                        Section {
                                            if !showfmintabs {
                                                NavigationLink {
                                                    SantanderView(startPath: "/")
                                                } label: {
                                                    Label("File Manager", systemImage: "folder")
                                                }
                                            }

                                            NavigationLink {
                                                CustomView(mgr: mgr)
                                            } label: {
                                                Label("Custom Overwrite", systemImage: "pencil")
                                            }

                                            NavigationLink {
                                                EditorView()
                                            } label: {
                                                Label("MobileGestalt", systemImage: "gear")
                                            }
                                        } header: {
                                            Text("Filesystem")
                                        }

                                        Section {
                                            NavigationLink {
                                                VarCleanView()
                                            } label: {
                                                Label("VarClean", systemImage: "sparkles")
                                            }
                                        } header: {
                                            Text("Cleanup")
                                        }

                                        if 1 == 2 {
                                            NavigationLink("Control Center") {
                                                CCView()
                                            }
                                        }
                                    }
                                    .navigationTitle(Text("Tweaks"))
                                }
                            }
                        }
                    } header: {
                        Text(selectedmethod == .vfs ? "Virtual File System" : (selectedmethod == .sbx ? "Sandbox Escape" : "Hybrid (SBX + VFS)"))
                    } footer: {
                        if selectedmethod == .sbx {
                            Text("Font Overwrite is only available in VFS or Hybrid mode. (Settings -> Method -> VFS/Hybrid)")
                        }
                    }

                    #if !DISABLE_REMOTECALL
                    Section {
                        Button {
                            mgr.logmsg("T")
                            mgr.rcinit(process: "SpringBoard", migbypass: false) { success in
                                if success {
                                    mgr.logmsg("rc init succeeded!")
                                    let pid = mgr.rccall(name: "getpid")
                                    mgr.logmsg("remote getpid() returned: \(pid)")
                                } else {
                                    mgr.logmsg("rc init failed")
                                }
                            }
                        } label: {
                            if mgr.rcrunning {
                                Text("Initialising RemoteCall...")
                            } else if !mgr.rcready {
                                Text("Initialise RemoteCall")
                            } else {
                                HStack {
                                    Text("Initialised RemoteCall")
                                    Spacer()
                                    Image(systemName: "checkmark.circle")
                                        .foregroundColor(.green)
                                }
                            }
                        }
                        .disabled(!mgr.dsready || mgr.rcready)
                        .disabled(isdebugged())

                        if mgr.rcready {
                            NavigationLink("Tweaks") {
                                RemoteView(mgr: mgr)
                            }

                            Button("Destroy RemoteCall") {
                                mgr.rcdestroy()
                            }
                        }
                        
                        if isdebugged() {
                            Button {
                                exit(0)
                            } label: {
                                Text("Detach")
                            }
                            .foregroundColor(.red)
                        }
                    } header: {
                        Text("RemoteCall")
                    } footer: {
                        if let error = mgr.rcLastError ?? mgr.sbProc?.lastError {
                            Text("Error: \(error)")
                                .foregroundColor(.red)
                        }
                        if RemoteCall.isLiveContainerRuntime() && !RemoteCall.isLiveProcessRuntime() {
                            Text("RemoteCall needs a PAC-enabled LiveContainer launch context. The main exploit may still work when RemoteCall is unavailable.")
                        }
                        if isdebugged() {
                            Text("Not available when a debugger is attached.")
                        }
                        Text("RemoteCall is still in development and may not work properly 100% of the time.")
                    }
                    .disabled(mgr.rcrunning)
                    #endif

                    Section {
                        if mgr.dsready {
                            NavigationLink("Tools") {
                                ToolsView()
                            }
                        }

                        Button("Respring") {
                            mgr.respring()
                        }

                        Button("Panic!") {
                            mgr.panic()
                        }
                        .disabled(!mgr.dsready)
                    } header: {
                        Text("Other")
                    }
                }

            }
            .navigationTitle("lara")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showsettings = true
                    } label: {
                        Image(systemName: "gear")
                    }
                }
            }
        }
        .sheet(isPresented: $showsettings) {
            SettingsView()
        }
        .onAppear {
            refreshselectedmethod()
        }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            refreshselectedmethod()
        }
    }

    private func refreshselectedmethod() {
        if let raw = UserDefaults.standard.string(forKey: "selectedmethod"),
           let m = method(rawValue: raw) {
            selectedmethod = m
        }
    }
}
