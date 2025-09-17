//
//  ContentView.swift
//  StikAI
//
//  Created by Stephen Bove on 9/17/25.
//

import SwiftUI
import Combine
import FoundationModels

// MARK: - Models

struct Message: Identifiable, Codable, Hashable {
    let id: UUID = UUID()
    var text: String
    var isUser: Bool
    var timestamp: Date = Date()
}

struct Chat: Identifiable, Codable, Hashable {
    let id: UUID = UUID()
    var title: String
    var messages: [Message]
}

// MARK: - Persistence

class ChatStore: ObservableObject {
    @Published var chats: [Chat] = []
    private let saveURL: URL
    
    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        saveURL = docs.appendingPathComponent("chats.json")
        load()
    }
    
    func load() {
        guard let data = try? Data(contentsOf: saveURL) else { return }
        if let decoded = try? JSONDecoder().decode([Chat].self, from: data) {
            chats = decoded
        }
    }
    
    func save() {
        if let data = try? JSONEncoder().encode(chats) {
            try? data.write(to: saveURL)
        }
    }
    
    func addChat(title: String = "New Chat") -> Chat {
        let newChat = Chat(title: title, messages: [])
        chats.insert(newChat, at: 0)
        save()
        return newChat
    }
    
    func updateChat(_ chat: Chat) {
        if let index = chats.firstIndex(where: { $0.id == chat.id }) {
            chats[index] = chat
            save()
        }
    }
    
    func clearAll() {
        chats.removeAll()
        save()
    }
    
    func deleteChat(_ chat: Chat) {
        chats.removeAll { $0.id == chat.id }
        save()
    }
    
    func renameChat(_ chat: Chat, newTitle: String) {
        if let index = chats.firstIndex(where: { $0.id == chat.id }) {
            chats[index].title = newTitle
            save()
        }
    }
}

// MARK: - Chat List View

struct ChatListView: View {
    @StateObject private var store = ChatStore()
    @State private var path: [Chat] = []
    @State private var showingSettings = false
    
    @State private var renamingChat: Chat? = nil
    @State private var renameText: String = ""
    
    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                LinearGradient(colors: [.blue.opacity(0.15), .purple.opacity(0.15)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                    .ignoresSafeArea()
                
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(store.chats, id: \.id) { chat in
                            NavigationLink(value: chat) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(chat.title)
                                        .font(.headline)
                                        .foregroundColor(.primary)
                                    
                                    if let last = chat.messages.last {
                                        Text(last.text)
                                            .font(.subheadline)
                                            .lineLimit(1)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(16)
                                .background(
                                    .ultraThinMaterial,
                                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                                )
                                .shadow(color: .black.opacity(0.1), radius: 6, x: 0, y: 3)
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal)
                            .contextMenu {
                                Button {
                                    renamingChat = chat
                                    renameText = chat.title
                                } label: {
                                    Label("Rename", systemImage: "pencil")
                                }
                                Button(role: .destructive) {
                                    store.deleteChat(chat)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .padding(.vertical)
                }
            }
            .navigationTitle("StikAI")
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button { showingSettings = true } label: {
                        Image(systemName: "gear")
                    }
                    Button {
                        let newChat = store.addChat()
                        path.append(newChat)
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                }
            }
            .navigationDestination(for: Chat.self) { chat in
                ChatView(chat: chat, store: store)
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView(store: store)
                    .presentationDetents([.fraction(0.50)])
                    .presentationDragIndicator(.visible)
            }
            .alert("Rename Chat", isPresented: Binding(
                get: { renamingChat != nil },
                set: { if !$0 { renamingChat = nil } }
            )) {
                TextField("Chat title", text: $renameText)
                Button("Save") {
                    if let chat = renamingChat {
                        store.renameChat(chat, newTitle: renameText)
                    }
                    renamingChat = nil
                }
                Button("Cancel", role: .cancel) {
                    renamingChat = nil
                }
            }
        }
    }
}

// MARK: - Chat View

struct ChatView: View {
    @State var chat: Chat
    @ObservedObject var store: ChatStore
    
    @State private var inputText = ""
    @State private var isProcessing = false
    
    @State private var renaming = false
    @State private var renameText = ""
    
    let systemModel = SystemLanguageModel.default
    @State private var session = LanguageModelSession()
    
    var body: some View {
        ZStack {
            LinearGradient(colors: [.blue.opacity(0.15), .purple.opacity(0.15)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()
            
            VStack {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            ForEach(chat.messages, id: \.id) { message in
                                VStack(alignment: message.isUser ? .trailing : .leading, spacing: 6) {
                                    HStack(alignment: .bottom, spacing: 8) {
                                        if message.isUser {
                                            Spacer()
                                            bubble(for: message)
                                            Image(systemName: "person.circle.fill")
                                                .font(.system(size: 28))
                                                .foregroundColor(.blue)
                                        } else {
                                            Image(systemName: "sparkles")
                                                .font(.system(size: 24))
                                                .foregroundColor(.green)
                                            bubble(for: message)
                                            Spacer()
                                        }
                                    }
                                    Text(message.timestamp, style: .time)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                .id(message.id)
                                .padding(.horizontal)
                            }
                        }
                        .padding(.vertical)
                    }
                    // 👇 Improved auto-scroll
                    .onChange(of: chat.messages) { _ in
                        if let lastId = chat.messages.last?.id {
                            withAnimation {
                                proxy.scrollTo(lastId, anchor: .bottom)
                            }
                        }
                    }
                    .onAppear {
                        if let lastId = chat.messages.last?.id {
                            DispatchQueue.main.async {
                                proxy.scrollTo(lastId, anchor: .bottom)
                            }
                        }
                    }
                }
                
                inputBar
                    .padding(.horizontal)
                    .padding(.bottom, 8)
            }
        }
        .navigationTitle(chat.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button {
                    renameText = chat.title
                    renaming = true
                } label: {
                    Image(systemName: "pencil")
                }
                Button(action: clearMessages) {
                    Image(systemName: "trash")
                }
            }
        }
        .onDisappear {
            store.updateChat(chat)
        }
        .alert("Rename Chat", isPresented: $renaming) {
            TextField("Chat title", text: $renameText)
            Button("Save") {
                chat.title = renameText
                store.renameChat(chat, newTitle: renameText)
            }
            Button("Cancel", role: .cancel) { }
        }
    }
    
    func bubble(for message: Message) -> some View {
        Text(message.text)
            .font(.body)
            .foregroundColor(message.isUser ? .white : .primary)
            .textSelection(.enabled)
            .padding(14)
            .background(
                message.isUser
                ? AnyShapeStyle(Color.blue)
                : AnyShapeStyle(.ultraThinMaterial),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
            .frame(maxWidth: 280, alignment: message.isUser ? .trailing : .leading)
    }
    
    var inputBar: some View {
        HStack(spacing: 12) {
            TextField("Ask privately…", text: $inputText, axis: .vertical)
                .padding(10)
                .background(
                    .ultraThinMaterial,
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                )
            
            Button(action: sendMessage) {
                if isProcessing {
                    ProgressView()
                } else {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 22))
                        .foregroundColor(inputText.isEmpty ? .gray : .blue)
                }
            }
            .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isProcessing)
        }
    }
    
    // MARK: - Actions
    
    func sendMessage() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        let userMessage = Message(text: trimmed, isUser: true)
        chat.messages.append(userMessage)
        inputText = ""
        
        if chat.messages.count == 1 {
            chat.title = trimmed
        }
        
        Task {
            guard systemModel.availability == .available else {
                chat.messages.append(Message(text: "Model not available.", isUser: false))
                return
            }
            
            isProcessing = true
            do {
                var aiResponse = Message(text: "…", isUser: false)
                chat.messages.append(aiResponse)
                let index = chat.messages.count - 1
                
                for try await partial in try await session.streamResponse(to: trimmed) {
                    aiResponse.text = partial.content
                    chat.messages[index] = aiResponse
                }
            } catch {
                chat.messages.append(Message(text: "Error: \(error.localizedDescription)", isUser: false))
            }
            isProcessing = false
            store.updateChat(chat)
        }
    }
    
    func clearMessages() {
        chat.messages.removeAll()
        store.updateChat(chat)
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @ObservedObject var store: ChatStore
    @Environment(\.dismiss) var dismiss
    @AppStorage("useDarkMode") private var useDarkMode = false
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle(isOn: $useDarkMode) {
                        Label("Dark Mode", systemImage: "moon.fill")
                    }
                }
                
                Section {
                    Button(role: .destructive) {
                        store.clearAll()
                        dismiss()
                    } label: {
                        Label("Clear All Chats", systemImage: "trash")
                    }
                }
                
                Section("About") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("StikAI is an on-device AI app.")
                        Text("It runs privately on your device with no servers or cloud processing.")
                    }
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 4)
                }
            }
            .scrollContentBackground(.hidden)
            .background(
                LinearGradient(colors: [.blue.opacity(0.15), .purple.opacity(0.15)],
                               startPoint: .topLeading,
                               endPoint: .bottomTrailing)
                .ignoresSafeArea()
            )
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(useDarkMode ? .dark : .light)
    }
}
