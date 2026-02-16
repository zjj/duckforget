import SwiftUI
import SwiftData

struct NoteSearchPage: View {
    @Environment(NoteStore.self) var noteStore
    @Environment(\.dismiss) private var dismiss
    
    @State private var searchText = ""
    @FocusState private var isSearchFocused: Bool
    
    // Speech recognition
    @StateObject private var speechRecognizer = SpeechRecognizer()
    @State private var voiceDragOffset: CGFloat = 0
    @State private var isVoiceButtonPressed = false
    
    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // Search Bar Area
                VStack(spacing: 12) {
                    HStack(spacing: 12) {
                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(.secondary)
                            
                            TextField("搜索所有备忘录...", text: $searchText)
                                .focused($isSearchFocused)
                                .submitLabel(.search)
                        }
                        .padding(10)
                        .background(Color(.systemGray6))
                        .cornerRadius(10)
                        
                        if !searchText.isEmpty {
                            Button("取消") {
                                searchText = ""
                                isSearchFocused = false
                            }
                            .foregroundColor(.accentColor)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                    .padding(.bottom, 8)
                }
                .background(Color(.systemBackground))
                .shadow(color: Color.black.opacity(0.05), radius: 2, y: 1)
                
                // Search Results
                NoteListView(folder: nil, showAllNotes: true, initialSearchText: searchText, hideSearchBar: true)
                    .environment(noteStore)
            }

            // Floating Voice UI (centered at bottom)
            ZStack(alignment: .bottom) {
                // Voice Input Overlay (shows while recording)
                SearchVoiceInputOverlay(
                    transcript: speechRecognizer.currentTranscript,
                    isRecording: speechRecognizer.isRecording,
                    dragOffset: 0,
                    shouldCancel: voiceDragOffset < -80
                )
                .offset(y: voiceDragOffset)
                .padding(.bottom, 80)
                .opacity(speechRecognizer.isRecording ? 1 : 0)
                .scaleEffect(speechRecognizer.isRecording ? 1 : 0.5, anchor: .bottom)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: speechRecognizer.isRecording)
                
                // Microphone button
                floatingVoiceButton
                    .padding(.bottom, 80)
                    .opacity(speechRecognizer.isRecording ? 0 : 1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .navigationTitle("搜索")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // Auto focus on open
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                isSearchFocused = true
            }
        }
        .onChange(of: speechRecognizer.currentTranscript) { _, newValue in
            if !newValue.isEmpty {
                searchText = newValue
            }
        }
    }
    
    private var floatingVoiceButton: some View {
        ZStack {
            Circle()
                .fill(Color.accentColor)
                .frame(width: 64, height: 64)
                .shadow(color: Color.black.opacity(0.2), radius: 8, x: 0, y: 4)
            
            Image(systemName: "mic.fill")
                .font(.system(size: 28))
                .foregroundColor(.white)
        }
        .scaleEffect(isVoiceButtonPressed ? 1.1 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isVoiceButtonPressed)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if !isVoiceButtonPressed {
                        isVoiceButtonPressed = true
                        speechRecognizer.startRecording()
                        let generator = UIImpactFeedbackGenerator(style: .medium)
                        generator.impactOccurred()
                    }
                    voiceDragOffset = value.translation.height
                }
                .onEnded { _ in
                    isVoiceButtonPressed = false
                    if voiceDragOffset < -80 {
                        speechRecognizer.stopRecording() // Cancel/Stop
                    } else {
                        speechRecognizer.stopRecording()
                        if !speechRecognizer.currentTranscript.isEmpty {
                            searchText = speechRecognizer.currentTranscript
                        }
                    }
                    voiceDragOffset = 0
                }
        )
    }
}

// Re-using VoiceInputOverlay (Ensure it's accessible or defined)
struct SearchVoiceInputOverlay: View {
    let transcript: String
    let isRecording: Bool
    let dragOffset: CGFloat
    let shouldCancel: Bool
    
    var body: some View {
        VStack(spacing: 20) {
/* Lines 100-117 omitted from prompt but assuming typical implementation */
            VStack(spacing: 12) {
                Text(shouldCancel ? "松开手指取消" : (transcript.isEmpty ? "正在倾听..." : transcript))
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(shouldCancel ? .red : .primary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)
                
                if !shouldCancel {
                    HStack(spacing: 4) {
                        ForEach(0..<5) { i in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.accentColor)
                                .frame(width: 4, height: CGFloat.random(in: 10...30))
                                .animation(.easeInOut(duration: 0.5).repeatForever().delay(Double(i) * 0.1), value: isRecording)
                        }
                    }
                }
            }
            .padding(.vertical, 30)
            .frame(width: 300)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color(.systemBackground))
                    .shadow(color: Color.black.opacity(0.15), radius: 20)
            )
            
            if !shouldCancel {
                Label("向上滑动取消", systemImage: "chevron.up")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 40))
                    .foregroundColor(.red)
            }
        }
    }
}
