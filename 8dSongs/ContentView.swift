
import SwiftUI
import AVFoundation
import MediaPlayer
import MusicKit

// Main ContentView
struct ContentView: View {
    @StateObject private var audioManager = AudioManager()
    @State private var showMusicPicker = false
    @State private var showFilePicker = false
    @State private var showURLInput = false
    @State private var urlString = ""
    
    var body: some View {
        VStack {
            Text("8D Audio Player")
                .font(.largeTitle)
                .padding()
            
            // Music source buttons
            HStack(spacing: 20) {
                Button("Local Files") {
                    showFilePicker = true
                }
                Button("Apple Music") {
                    showMusicPicker = true
                }
                Button("URL") {
                    showURLInput = true
                }
            }
            .padding()
            
            // Player controls
            if audioManager.isLoaded {
                PlayerControlsView(audioManager: audioManager)
            }
            
            Spacer()
        }
        .sheet(isPresented: $showMusicPicker) {
            MusicPickerView(audioManager: audioManager)
        }
        .sheet(isPresented: $showFilePicker) {
            DocumentPicker(audioManager: audioManager)
        }
        .alert("Enter URL", isPresented: $showURLInput) {
            TextField("Audio URL", text: $urlString)
            Button("Load") {
                if let url = URL(string: urlString) {
                    audioManager.loadAudio(from: url)
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}

// Audio Manager to handle playback and effects
class AudioManager: ObservableObject {
    private var engine: AVAudioEngine?
    private var player: AVAudioPlayer?
    private var playerNode: AVAudioPlayerNode?
    private var rotationTimer: Timer?
    
    @Published var isPlaying = false
    @Published var isLoaded = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var rotationSpeed: Double = 1.0
    
    // Audio processing nodes
    private let panNode = AVAudioMixerNode()
    private let reverbNode = AVAudioUnitReverb()
    private let equalizerNode = AVAudioUnitEQ(numberOfBands: 8)
    private let delayNode = AVAudioUnitDelay()
    private let distortionNode = AVAudioUnitDistortion()
    
    // 3D audio parameters
    private var currentAngle: Float = 0.0
    private var currentElevation: Float = 0.0
    private var currentDistance: Float = 1.0
    private var roomSize: Float = 0.5  // 0.0 to 1.0
    
    init() {
        setupAudioEngine()
    }
    
    private func setupAudioEngine() {
        engine = AVAudioEngine()
        playerNode = AVAudioPlayerNode()
        
        guard let engine = engine,
              let playerNode = playerNode else { return }
        
        // Attach all nodes
        engine.attach(playerNode)
        engine.attach(panNode)
        engine.attach(reverbNode)
        engine.attach(equalizerNode)
        engine.attach(delayNode)
        engine.attach(distortionNode)
        
        // Configure audio effects
        configureAudioEffects()
        
        // Create processing chain: player -> EQ -> delay -> distortion -> reverb -> pan -> output
        engine.connect(playerNode, to: equalizerNode, format: nil)
        engine.connect(equalizerNode, to: delayNode, format: nil)
        engine.connect(delayNode, to: distortionNode, format: nil)
        engine.connect(distortionNode, to: reverbNode, format: nil)
        engine.connect(reverbNode, to: panNode, format: nil)
        engine.connect(panNode, to: engine.mainMixerNode, format: nil)
        
        do {
            // Set up audio session for optimal audio quality
            try AVAudioSession.sharedInstance().setCategory(.playback,
                mode: .default,
                options: [.allowBluetoothA2DP, .duckOthers])
            
            // Configure audio session for best quality
            try AVAudioSession.sharedInstance().setPreferredIOBufferDuration(0.005) // Lower latency
            try AVAudioSession.sharedInstance().setPreferredSampleRate(96000) // High quality sample rate
            try AVAudioSession.sharedInstance().setActive(true)
            
            try engine.start()
        } catch {
            print("Error starting audio engine: \(error)")
        }
    }
    
    private func configureAudioEffects() {
        // Configure reverb for enhanced room simulation
        reverbNode.loadFactoryPreset(.cathedral) // More spacious reverb
        reverbNode.wetDryMix = 25 // Balanced reverb mix
        
        // Configure EQ for frequency enhancement
        if let bands = equalizerNode.bands as? [AVAudioUnitEQFilterParameters] {
            // Sub-bass for depth
            bands[0].frequency = 40
            bands[0].gain = 2
            bands[0].bandwidth = 0.7
            
            // Bass for presence
            bands[1].frequency = 120
            bands[1].gain = 3
            bands[1].bandwidth = 0.8
            
            // Lower-mids for warmth
            bands[2].frequency = 500
            bands[2].gain = 1
            bands[2].bandwidth = 1.0
            
            // Upper-mids for spatial clarity
            bands[3].frequency = 2000
            bands[3].gain = 2.5
            bands[3].bandwidth = 1.0
            
            // Presence for position perception
            bands[4].frequency = 4000
            bands[4].gain = 3
            bands[4].bandwidth = 0.8
            
            // Brilliance for space
            bands[5].frequency = 8000
            bands[5].gain = 2
            bands[5].bandwidth = 0.7
            
            // Air frequencies
            bands[6].frequency = 12000
            bands[6].gain = 0.5
            bands[6].bandwidth = 0.5
            
            bands[7].frequency = 16000
            bands[7].gain = 0.3
            bands[7].bandwidth = 0.5
        }
        
        // Configure delay for subtle depth
        delayNode.wetDryMix = 10
        delayNode.delayTime = 0.02 // Very short delay for spatial enhancement
        delayNode.feedback = 10
        
        // Configure distortion for subtle harmonics
        distortionNode.loadFactoryPreset(.drumsLoFi)
        distortionNode.wetDryMix = 5 // Very subtle distortion
    }
    
    func loadAudio(from url: URL) {
        // Stop any existing playback
        stop()
        
        do {
            // Create audio session
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            
            // For local files, try to create a local copy first
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let destinationUrl = documentsPath.appendingPathComponent(url.lastPathComponent)
            
            if url.isFileURL {
                // For local files, try to copy to app's document directory
                try? FileManager.default.removeItem(at: destinationUrl)
                try FileManager.default.copyItem(at: url, to: destinationUrl)
            }
            
            // Try to load the audio file
            let audioFile: AVAudioFile
            if url.isFileURL {
                audioFile = try AVAudioFile(forReading: destinationUrl)
            } else {
                // For remote URLs, download the data first
                let data = try Data(contentsOf: url)
                try data.write(to: destinationUrl)
                audioFile = try AVAudioFile(forReading: destinationUrl)
            }
            
            let audioFormat = audioFile.processingFormat
            
            guard let playerNode = playerNode else {
                print("Player node not initialized")
                return
            }
            
            // Reset the engine
            engine?.stop()
            try? engine?.start()
            
            playerNode.stop()
            playerNode.scheduleFile(audioFile, at: nil)
            duration = Double(audioFile.length) / audioFormat.sampleRate
            isLoaded = true
            
            // Start rotation timer
            startPanRotation()
            
        } catch {
            print("Error loading audio: \(error)")
            // Reset state
            isLoaded = false
            duration = 0
            currentTime = 0
        }
    }
    
    private func startPanRotation() {
        rotationTimer?.invalidate()
        
        rotationTimer = Timer.scheduledTimer(withTimeInterval: 0.016, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            // Smooth rotation speed with balance
            self.currentAngle += Float(0.002 * self.rotationSpeed)
            if self.currentAngle > .pi * 4 {
                self.currentAngle -= .pi * 7
            }
            
            // Add elevation for 3D rotation
            self.currentElevation = sin(self.currentAngle * 0.4) * 0.5  // Adjust the multiplier for smoother up/down motion
            
            // Calculate spherical position (3D space)
            let radius = self.currentDistance
            let x = cos(self.currentAngle) * radius
            let y = sin(self.currentAngle) * radius
            let z = sin(self.currentElevation) * radius  // Elevation effect

            // Update pan and volume based on position
            let pan = Float(x / radius) // Pan left/right
            let distanceFactor = 05.0 - (abs(z) * 0.2) // Use Z-axis for distance (forward/back)
            
            self.panNode.pan = pan
            self.playerNode?.volume = distanceFactor
            
            // Apply smoother reverb and delay adjustments
            let reverbAmount = 20 + (abs(y) * 10)  // More reverb when further away
            self.reverbNode.wetDryMix = reverbAmount
            
            let delayTime = 0.02 + (abs(x) * 0.005)
            self.delayNode.delayTime = Double(delayTime)
            
            // Adjust room size simulation for more realistic effects
            let roomSimulation = 0.3 + (abs(sin(self.currentAngle * 0.25)) * 0.3)
            self.reverbNode.wetDryMix = 20 + (roomSimulation * 15)
        }
    }

    func setRotationSpeed(_ speed: Double) {
        // Default speed is now 1.0, can be adjusted from 0.2 to 2.0
        rotationSpeed = max(0.2, min(2.0, speed))
    }
    
    func setRoomSize(_ size: Float) {
        roomSize = max(0.0, min(1.0, size))
        reverbNode.wetDryMix = roomSize * 50
    }
    
    func play() {
        guard let playerNode = playerNode else { return }
        playerNode.play()
        isPlaying = true
        
        // Update current time
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] timer in
            guard let self = self,
                  self.isPlaying else {
                timer.invalidate()
                return
            }
            
            if let nodeTime = playerNode.lastRenderTime,
               let playerTime = playerNode.playerTime(forNodeTime: nodeTime) {
                self.currentTime = Double(playerTime.sampleTime) / playerTime.sampleRate
            }
        }
    }
    
    func pause() {
        playerNode?.pause()
        isPlaying = false
    }
    
    func stop() {
        playerNode?.stop()
        isPlaying = false
        currentTime = 0
    }
}

// Document Picker for local files
struct DocumentPicker: UIViewControllerRepresentable {
    let audioManager: AudioManager
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.audio])
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: DocumentPicker
        
        init(_ parent: DocumentPicker) {
            self.parent = parent
        }
        
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            // Start accessing the security-scoped resource
            guard url.startAccessingSecurityScopedResource() else {
                print("Failed to access security scoped resource")
                return
            }
            
            parent.audioManager.loadAudio(from: url)
            
            // Stop accessing the security-scoped resource
            url.stopAccessingSecurityScopedResource()
        }
    }
}

// Music Picker for Apple Music
struct MusicPickerView: View {
    let audioManager: AudioManager
    @Environment(\.dismiss) var dismiss
    @State private var searchTerm = ""
    @State private var songs: [Song] = []
    @State private var isAuthorized = false
    
    func requestMusicAuthorization() {
        Task {
            let status = await MusicAuthorization.request()
            await MainActor.run {
                isAuthorized = status == .authorized
            }
        }
    }
    
    var body: some View {
        NavigationView {
            Group {
                if isAuthorized {
            List(songs, id: \.id) { song in
                Button(action: {
                    loadSong(song)
                }) {
                    VStack(alignment: .leading) {
                        Text(song.title)
                        Text(song.artistName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .searchable(text: $searchTerm)
            .onChange(of: searchTerm) { _ in
                searchMusic()
            }
            .navigationTitle("Apple Music")
                } else {
                    VStack {
                        Text("Music access not authorized")
                        Button("Request Authorization") {
                            requestMusicAuthorization()
                        }
                    }
                }
            }
        }
        .onAppear {
            requestMusicAuthorization()
        }
    }
    
    private func searchMusic() {
        Task {
            do {
                let request = MusicCatalogSearchRequest(term: searchTerm, types: [Song.self])
                let response = try await request.response()
                songs = response.songs.map { $0 }
            } catch {
                print("Error searching music: \(error)")
            }
        }
    }
    
    private func loadSong(_ song: Song) {
        Task {
            if let url = song.previewAssets?.first?.url {
                audioManager.loadAudio(from: url)
                dismiss()
            }
        }
    }
}

// Player Controls View
struct PlayerControlsView: View {
    @ObservedObject var audioManager: AudioManager
    
    var body: some View {
        VStack {
            // Progress bar
            Slider(value: .constant(audioManager.currentTime),
                   in: 0...audioManager.duration)
                .disabled(true)
                .padding()
            
            // Time labels
            HStack {
                Text(formatTime(audioManager.currentTime))
                Spacer()
                Text(formatTime(audioManager.duration))
            }
            .font(.caption)
            .padding(.horizontal)
            
            // Playback controls
            HStack(spacing: 40) {
                Button(action: {
                    audioManager.stop()
                }) {
                    Image(systemName: "stop.fill")
                        .font(.title)
                }
                
                Button(action: {
                    if audioManager.isPlaying {
                        audioManager.pause()
                    } else {
                        audioManager.play()
                    }
                }) {
                    Image(systemName: audioManager.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title)
                }
            }
            .padding()
        }
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
