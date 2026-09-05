//
//  ConnectView.swift
//  SwiftGups
//
//  Connect Tab - Death Stranding inspired interface for building bridges between students
//

import SwiftUI
import CloudKit
import UIKit
import os.log

// MARK: - Connect Tab

struct ConnectTab: View {
    let currentUser: User
    let isInSplitView: Bool
    @StateObject private var connectService = ConnectService()
    @State private var showingParticles = false
    @State private var animateText = false
    @State private var bridgeAnimation = false
    @State private var showKojimaEasterEgg = false
    
    var body: some View {
        SwiftUI.Group {
            if isInSplitView {
                // iPad layout
                connectContent
                    .navigationTitle("Connect")
                    .navigationBarTitleDisplayMode(.large)
            } else {
                // iPhone layout
                NavigationView {
                    connectContent
                        .navigationTitle("Connect")
                        .navigationBarTitleDisplayMode(.large)
                }
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.5)) {
                animateText = true
            }
            withAnimation(.easeInOut(duration: 2.0).delay(0.5)) {
                bridgeAnimation = true
            }
        }
    }
    
    @ViewBuilder
    private var connectContent: some View {
        ZStack {
            // Death Stranding inspired background
            DeathStrandingBackground(showParticles: $showingParticles)
            
            ScrollView {
                VStack(spacing: 32) {
                    // Hero Section
                    VStack(spacing: 20) {
                        // Animated Icon with enhanced Death Stranding style
                        ZStack {
                            // Основной круг с глубоким градиентом
                            Circle()
                                .fill(
                                    RadialGradient(
                                        colors: [.cyan.opacity(0.8), .blue.opacity(0.6), .black],
                                        center: .center,
                                        startRadius: 30,
                                        endRadius: 100
                                    )
                                )
                                .frame(width: 180, height: 180)
                                .scaleEffect(bridgeAnimation ? 1.05 : 0.95)
                                .shadow(color: .cyan.opacity(0.8), radius: 30, x: 0, y: 0)
                            
                            // Кольцо свечения
                            Circle()
                                .stroke(
                                    LinearGradient(
                                        colors: [.cyan, .blue.opacity(0.5), .clear],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 3
                                )
                                .frame(width: 200, height: 200)
                                .rotationEffect(.degrees(bridgeAnimation ? 360 : 0))
                                .animation(.linear(duration: 8.0).repeatForever(autoreverses: false), value: bridgeAnimation)
                            
                            // Основная иконка с улучшенным контрастом и секретным жестом
                            VStack(spacing: 8) {
                                ZStack {
                                    // Тень для иконки
                                    Image(systemName: "link.circle.fill")
                                        .font(.system(size: 60))
                                        .foregroundColor(.black.opacity(0.8))
                                        .offset(x: 2, y: 2)
                                    
                                    Image(systemName: "link.circle.fill")
                                        .font(.system(size: 60))
                                        .foregroundStyle(
                                            LinearGradient(
                                                colors: [.white, .cyan.opacity(0.9), .blue.opacity(0.8)],
                                                startPoint: .top,
                                                endPoint: .bottom
                                            )
                                        )
                                        .shadow(color: .cyan, radius: 8)
                                }
                                .scaleEffect(bridgeAnimation ? 1.1 : 0.9)
                                // Секретный жест для пасхалки Кодзимы
                                .onLongPressGesture(
                                    minimumDuration: 2.0,
                                    maximumDistance: 50.0
                                ) {
                                    print("🎮 Long press detected! Bridges: \(connectService.stats.bridgesBuilt), Has achievement: \(connectService.stats.hasKojimaAchievement)")
                                    
                                    if connectService.stats.hasKojimaAchievement {
                                        let impact = UIImpactFeedbackGenerator(style: .heavy)
                                        impact.impactOccurred()
                                        
                                        print("🎮 Activating Kojima easter egg!")
                                        
                                        withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                                            showKojimaEasterEgg = true
                                        }
                                    } else {
                                        print("🎮 Achievement not unlocked yet. Need 5+ bridges, current: \(connectService.stats.bridgesBuilt)")
                                        
                                        // Показываем подсказку для недостаточного уровня
                                        let softImpact = UIImpactFeedbackGenerator(style: .light)
                                        softImpact.impactOccurred()
                                    }
                                } onPressingChanged: { pressing in
                                    // Визуальная обратная связь
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        if pressing && connectService.stats.hasKojimaAchievement {
                                            // Показываем что жест активен
                                        }
                                    }
                                }
                                
                                // Улучшенные точки с контрастом
                                HStack(spacing: 8) {
                                    ForEach(0..<3, id: \.self) { index in
                                        Text("●")
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundColor(
                                                connectService.stats.hasKojimaAchievement ? .yellow : .cyan
                                            )
                                            .shadow(color: .black, radius: 2)
                                            .opacity(bridgeAnimation ? 1.0 : 0.7)
                                            .animation(
                                                .easeInOut(duration: 0.8)
                                                .delay(Double(index) * 0.2)
                                                .repeatForever(autoreverses: true),
                                                value: connectService.stats.hasKojimaAchievement
                                            )
                                    }
                                }
                            }
                        }
                        .rotation3DEffect(
                            .degrees(bridgeAnimation ? 5 : -5),
                            axis: (x: 1, y: 1, z: 0)
                        )
                        
                        // Title with Death Stranding style
                        VStack(spacing: 16) {
                            // Основной заголовок
                            Text("CONNECT")
                                .font(.system(size: 52, weight: .black, design: .default))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [.white, .cyan, .blue, .white],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .shadow(color: .cyan.opacity(0.8), radius: 15, x: 0, y: 0)
                                .shadow(color: .blue.opacity(0.4), radius: 25, x: 0, y: 10)
                                .scaleEffect(animateText ? 1.0 : 0.8)
                                .opacity(animateText ? 1.0 : 0.0)
                            
                            // Подзаголовок в стиле Death Stranding
                            VStack(spacing: 4) {
                                Text("BUILD BRIDGES")
                                    .font(.system(size: 22, weight: .medium, design: .monospaced))
                                    .foregroundColor(.cyan)
                                    .opacity(animateText ? 0.9 : 0.0)
                                
                                Text("━━━ RESTORE CONNECTION ━━━")
                                    .font(.system(size: 12, weight: .light, design: .monospaced))
                                    .foregroundColor(.cyan.opacity(0.6))
                                    .opacity(animateText ? 0.7 : 0.0)
                            }
                        }
                    }
                    
                    // Narrative Section
                    VStack(spacing: 24) {
                        NarrativeCard(
                            icon: "person.2.circle",
                            title: "Мы все связаны",
                            text: "В мире, где каждый студент - это остров, мы строим мосты между сердцами и разумами.",
                            animateText: animateText,
                            isInteractive: true
                        )
                        
                        NarrativeCard(
                            icon: "hand.point.up.braille",
                            title: "Каждое прикосновение имеет значение",
                            text: "Лайк не просто нажатие кнопки. Это сигнал в пустоту, что ты не один.",
                            animateText: animateText,
                            isInteractive: true
                        )
                        
                        NarrativeCard(
                            icon: "network",
                            title: "Создавая связи",
                            text: "Когда мы соединяемся, мы создаём сильное общество. Каждая связь делает нас человечнее.",
                            animateText: animateText,
                            isInteractive: true
                        )
                        
                        // Новая карточка о будущем сервиса
                        FutureServiceCard(animateText: animateText)
                    }
                    
                    // Connection Status
                    ConnectionStatusCard(
                        status: connectService.connectionStatus,
                        animateText: animateText
                    )
                    
                    // Stats and Like Section
                    VStack(spacing: 24) {
                        // Stats Card with achievement level
                        StatsCard(
                            stats: connectService.stats,
                            bridgeAnimation: bridgeAnimation,
                            showAchievementLevel: true
                        )
                        
                        // Like Button (Death Stranding style)
                        DeathStrandingLikeButton(
                            isLoading: connectService.isLoading,
                            onTap: {
                                Task {
                                    await connectService.addLike()
                                    withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
                                        showingParticles = true
                                    }
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                                        showingParticles = false
                                    }
                                }
                            }
                        )
                    }
                    
                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
            }
        }
        .background(Color.black)
        .preferredColorScheme(.dark)
        .task {
            await connectService.loadStats()
        }
        .fullScreenCover(isPresented: $showKojimaEasterEgg) {
            KojimaEasterEggView(isPresented: $showKojimaEasterEgg)
        }
    }
}

// MARK: - Death Stranding Components

struct DeathStrandingBackground: View {
    @Binding var showParticles: Bool
    @State private var animate = false
    
    var body: some View {
        ZStack {
            // Base black background
            Color.black
                .ignoresSafeArea()
            
            // Animated gradient overlay
            RadialGradient(
                colors: [
                    .cyan.opacity(0.1),
                    .blue.opacity(0.05),
                    .black
                ],
                center: .center,
                startRadius: 100,
                endRadius: 400
            )
            .ignoresSafeArea()
            .opacity(animate ? 0.8 : 0.5)
            .animation(.easeInOut(duration: 4.0).repeatForever(autoreverses: true), value: animate)
            
            // Particle effect
            if showParticles {
                ParticleEffect()
                    .ignoresSafeArea()
            }
        }
        .onAppear {
            animate = true
        }
    }
}

struct NarrativeCard: View {
    let icon: String
    let title: String
    let text: String
    let animateText: Bool
    let isInteractive: Bool
    @State private var isPressed = false
    @State private var showFullText = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(.cyan)
                    .frame(width: 30, height: 30)
                
                Text(title)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
            }
            
            Text(text)
                .font(.body)
                .foregroundColor(.gray)
                .lineSpacing(4)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(
                    LinearGradient(
                        colors: isPressed ? [.cyan.opacity(0.1), .black.opacity(0.9)] : [.black.opacity(0.8), .gray.opacity(0.1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(
                            LinearGradient(
                                colors: isPressed ? [.cyan.opacity(0.6), .clear] : [.cyan.opacity(0.3), .clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: isPressed ? 2 : 1
                        )
                )
        )
        .scaleEffect(isPressed ? 0.98 : (animateText ? 1.0 : 0.9))
        .opacity(animateText ? 1.0 : 0.0)
        .animation(.easeInOut(duration: 0.8).delay(0.2), value: animateText)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isPressed)
        .onLongPressGesture(minimumDuration: 0.1) {
            if isInteractive {
                let impact = UIImpactFeedbackGenerator(style: .light)
                impact.impactOccurred()
                
                withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                    showFullText.toggle()
                }
            }
        } onPressingChanged: { pressing in
            if isInteractive {
                withAnimation(.easeInOut(duration: 0.1)) {
                    isPressed = pressing
                }
            }
        }
    }
}

struct StatsCard: View {
    let stats: ConnectStats
    let bridgeAnimation: Bool
    let showAchievementLevel: Bool
    
    var body: some View {
        VStack(spacing: 20) {
            // Total Likes
            HStack {
                Image(systemName: "heart.fill")
                    .font(.title2)
                    .foregroundColor(.cyan)
                    .scaleEffect(bridgeAnimation ? 1.2 : 1.0)
                    .animation(.spring(response: 0.6, dampingFraction: 0.8).repeatForever(autoreverses: true), value: bridgeAnimation)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(stats.totalLikes)")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    
                    Text("Лайков получено")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                
                Spacer()
            }
            
            Divider()
                .background(Color.gray.opacity(0.3))
            
            // Bridges Built
            HStack {
                Image(systemName: "link")
                    .font(.title2)
                    .foregroundColor(.cyan)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(stats.bridgesBuiltText)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                    
                    Text("Мостов построено: \(stats.bridgesBuilt)")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                
                Spacer()
            }
            
            // Achievement Level (если включено)
            if showAchievementLevel {
                Divider()
                    .background(Color.gray.opacity(0.3))
                
                HStack {
                    Image(systemName: stats.hasKojimaAchievement ? "star.fill" : "star")
                        .font(.title2)
                        .foregroundColor(stats.hasKojimaAchievement ? .yellow : .cyan)
                        .symbolEffect(.pulse, value: stats.hasKojimaAchievement)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Уровень: \(stats.achievementLevel)")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                        
                        if stats.hasKojimaAchievement {
                            Text("Секретная функция доступна 🎮")
                                .font(.caption)
                                .foregroundColor(.yellow.opacity(0.8))
                        } else {
                            Text("Стройте больше мостов для новых функций")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                    }
                    
                    Spacer()
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(
                    LinearGradient(
                        colors: [.black.opacity(0.9), .gray.opacity(0.1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(
                            LinearGradient(
                                colors: [.cyan.opacity(0.5), .clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 2
                        )
                )
                .shadow(color: .cyan.opacity(0.3), radius: 15, x: 0, y: 8)
        )
    }
}

struct DeathStrandingLikeButton: View {
    let isLoading: Bool
    let onTap: () -> Void
    @State private var buttonScale: CGFloat = 1.0
    @State private var glowIntensity: Double = 0.0
    
    var body: some View {
        Button(action: {
            let impactFeedback = UIImpactFeedbackGenerator(style: .heavy)
            impactFeedback.impactOccurred()
            
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                buttonScale = 0.95
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    buttonScale = 1.0
                }
            }
            
            onTap()
        }) {
            HStack(spacing: 12) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(0.8)
                } else {
                    // Death Stranding thumbs up icon
                    Image(systemName: "hand.thumbsup.circle.fill")
                        .font(.title2)
                        .foregroundColor(.white)
                }
                
                Text(isLoading ? "Отправка..." : "Построить мост")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 60)
            .background(
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [.cyan, .blue, .cyan],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: .cyan.opacity(glowIntensity), radius: 25, x: 0, y: 0)
                    .shadow(color: .blue.opacity(0.4), radius: 15, x: 0, y: 8)
            )
        }
        .scaleEffect(buttonScale)
        .disabled(isLoading)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                glowIntensity = 0.8
            }
        }
    }
}

struct ParticleEffect: View {
    @State private var particles: [Particle] = []
    @State private var animationTimer: Timer?
    
    var body: some View {
        ZStack {
            ForEach(particles, id: \.id) { particle in
                ZStack {
                    // Основная частица
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [.cyan.opacity(particle.opacity), .blue.opacity(particle.opacity * 0.5), .clear],
                                center: .center,
                                startRadius: 0,
                                endRadius: particle.size / 2
                            )
                        )
                        .frame(width: particle.size, height: particle.size)
                    
                    // Свечение вокруг частицы
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [.cyan.opacity(particle.opacity * 0.8), .clear],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1
                        )
                        .frame(width: particle.size * 1.5, height: particle.size * 1.5)
                }
                .position(particle.position)
                .scaleEffect(particle.scale)
                .blur(radius: particle.size > 6 ? 1 : 0)
            }
        }
        .onAppear {
            generateParticles()
            startContinuousAnimation()
        }
        .onDisappear {
            animationTimer?.invalidate()
        }
    }
    
    private func generateParticles() {
        particles.removeAll()
        
        for _ in 0..<30 {
            let particle = Particle(
                position: CGPoint(
                    x: CGFloat.random(in: 0...UIScreen.main.bounds.width),
                    y: CGFloat.random(in: UIScreen.main.bounds.height...UIScreen.main.bounds.height + 100)
                ),
                size: CGFloat.random(in: 3...12),
                opacity: Double.random(in: 0.2...0.9),
                scale: CGFloat.random(in: 0.3...1.2)
            )
            particles.append(particle)
        }
    }
    
    private func startContinuousAnimation() {
        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            withAnimation(.linear(duration: 0.1)) {
                for i in 0..<particles.count {
                    // Движение вверх с небольшими колебаниями
                    particles[i].position.y -= CGFloat.random(in: 2...6)
                    particles[i].position.x += CGFloat.random(in: -1...1)
                    
                    // Постепенное исчезновение
                    particles[i].opacity *= 0.995
                    particles[i].scale *= 0.998
                    
                    // Если частица вышла за экран или стала невидимой
                    if particles[i].position.y < -50 || particles[i].opacity < 0.1 {
                        // Создаём новую частицу внизу экрана
                        particles[i] = Particle(
                            position: CGPoint(
                                x: CGFloat.random(in: 0...UIScreen.main.bounds.width),
                                y: CGFloat.random(in: UIScreen.main.bounds.height...UIScreen.main.bounds.height + 100)
                            ),
                            size: CGFloat.random(in: 3...12),
                            opacity: Double.random(in: 0.2...0.9),
                            scale: CGFloat.random(in: 0.3...1.2)
                        )
                    }
                }
            }
        }
    }
}

struct Particle: Identifiable {
    let id = UUID()
    var position: CGPoint
    var size: CGFloat
    var opacity: Double
    var scale: CGFloat
}

// MARK: - Connect Service

@MainActor
class ConnectService: ObservableObject {
    @Published var stats = ConnectStats()
    @Published var isLoading = false
    @Published var connectionStatus: ConnectionStatus = .unknown
    // showKojimaEasterEgg перенесена в ConnectTab для локального управления
    
    /// `nil` без iCloud-entitlement: `CKContainer.default()` там падает фатально,
    /// поэтому Connect работает полностью локально.
    private let container: CKContainer? = AppEnvironment.isCloudKitAvailable ? .default() : nil
    private var publicDatabase: CKDatabase? { container?.publicCloudDatabase }
    
    enum ConnectionStatus {
        case connected
        case offline
        case error(String)
        case unknown
        
        var description: String {
            switch self {
            case .connected:
                return "Подключен к сети мостов"
            case .offline:
                return "Автономный режим - строим локальные мосты"
            case .error(let message):
                return "Ошибка соединения: \(message)"
            case .unknown:
                return "Проверка соединения..."
            }
        }
        
        var icon: String {
            switch self {
            case .connected:
                return "wifi.circle.fill"
            case .offline:
                return "wifi.slash"
            case .error:
                return "exclamationmark.triangle.fill"
            case .unknown:
                return "questionmark.circle.fill"
            }
        }
        
        var color: Color {
            switch self {
            case .connected:
                return .green
            case .offline:
                return .orange
            case .error:
                return .red
            case .unknown:
                return .gray
            }
        }
    }
    
    func loadStats() async {
        // Загружаем локальные данные
        loadLocalStats()
        
        // Устанавливаем статус подключения как автономный режим до первой синхронизации  
        connectionStatus = .offline
        
        // Даем время CloudKitService настроить схему, затем пытаемся загрузить
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            Task {
                await self.attemptCloudKitSync()
            }
        }
        
        os_log("🔄 Connect service loaded in offline mode. Will attempt sync shortly.", log: .default, type: .info)
    }
    
    /// Попытка синхронизации с CloudKit (безопасно, без ошибок)
    private func attemptCloudKitSync() async {
        guard let container, let publicDatabase else {
            os_log("📡 CloudKit недоступен в этой сборке — остаёмся в локальном режиме", log: .default, type: .info)
            return
        }

        do {
            let accountStatus = try await container.accountStatus()
            guard accountStatus == .available else {
                os_log("📡 CloudKit account not available for sync", log: .default, type: .info)
                return
            }

            // Простая попытка подсчета записей
            let query = CKQuery(recordType: "ConnectLike", predicate: NSPredicate(format: "TRUEPREDICATE"))
            let result = try await publicDatabase.records(matching: query)
            let cloudCount = result.matchResults.count
            
            // Обновляем статистику если есть облачные данные
            if cloudCount > 0 {
                let localLikes = UserDefaults.standard.integer(forKey: "LocalConnectLikes")
                let totalLikes = max(cloudCount, localLikes)
                
                stats = ConnectStats(
                    totalLikes: totalLikes,
                    bridgesBuilt: calculateBridges(from: totalLikes)
                )
                
                saveLocalStats()
                connectionStatus = .connected
                os_log("✅ Synced with CloudKit: %d cloud likes, %d local likes", log: .default, type: .info, cloudCount, localLikes)
            } else {
                connectionStatus = .connected
                os_log("📡 Connected to CloudKit (no existing likes)", log: .default, type: .info)
            }
            
        } catch {
            // Не логируем как ошибку - это нормально если схема еще не готова
            os_log("📡 CloudKit sync not available yet: %@", log: .default, type: .info, error.localizedDescription)
        }
    }
    
    private func loadLocalStats() {
        let localLikes = UserDefaults.standard.integer(forKey: "LocalConnectLikes")
        let localBridges = UserDefaults.standard.integer(forKey: "LocalConnectBridges")
        
        stats = ConnectStats(
            totalLikes: localLikes,
            bridgesBuilt: localBridges
        )
    }
    
    private func saveLocalStats() {
        UserDefaults.standard.set(stats.totalLikes, forKey: "LocalConnectLikes")
        UserDefaults.standard.set(stats.bridgesBuilt, forKey: "LocalConnectBridges")
    }
    
    func addLike() async {
        isLoading = true
        
        // Сначала обновляем локально
        let newLikes = stats.totalLikes + 1
        stats = ConnectStats(
            totalLikes: newLikes,
            bridgesBuilt: calculateBridges(from: newLikes)
        )
        saveLocalStats()
        
        // Пасхалка Кодзимы теперь скрыта и активируется только секретным жестом
        // Пока что убираем автоматический показ
        
        // Пытаемся синхронизировать с CloudKit
        await syncWithCloudKit()
        
        isLoading = false
    }
    
    private func syncWithCloudKit() async {
        guard let container, let publicDatabase else {
            connectionStatus = .offline
            os_log("CloudKit недоступен в этой сборке, работаем в автономном режиме", log: .default, type: .info)
            return
        }

        let deviceId = await getDeviceIdentifier()
        let like = ConnectLike(deviceIdentifier: deviceId)

        do {
            // Проверяем статус аккаунта
            let accountStatus = try await container.accountStatus()

            guard accountStatus == .available else {
                connectionStatus = .offline
                os_log("CloudKit недоступен, работаем в автономном режиме", log: .default, type: .info)
                return
            }

            // Пытаемся сохранить в CloudKit
            let record = like.toCKRecord()
            _ = try await publicDatabase.save(record)
            
            connectionStatus = .connected
            os_log("✅ Like successfully synced with CloudKit", log: .default, type: .info)
            
        } catch {
            connectionStatus = .error(error.localizedDescription)
            os_log("❌ CloudKit sync failed: %@. Working offline.", log: .default, type: .error, error.localizedDescription)
            
            // В случае ошибки работаем локально
            // Данные уже сохранены локально выше
        }
    }
    
    private func getDeviceIdentifier() async -> String {
        return await withCheckedContinuation { continuation in
            if let identifier = UserDefaults.standard.string(forKey: "DeviceIdentifier") {
                continuation.resume(returning: identifier)
            } else {
                let newIdentifier = UUID().uuidString
                UserDefaults.standard.set(newIdentifier, forKey: "DeviceIdentifier")
                continuation.resume(returning: newIdentifier)
            }
        }
    }
    
    /// Рассчитывает количество мостов на основе лайков
    /// Логика: каждые 5 лайков = 1 мост, но с нелинейным ростом для интереса
    private func calculateBridges(from likes: Int) -> Int {
        switch likes {
        case 0:
            return 0
        case 1...4:
            return 1  // Первый мост появляется сразу
        case 5...19:
            return likes / 5 + 1
        case 20...99:
            return likes / 4 + 2
        default:
            return likes / 3 + 10  // Более быстрый рост для больших чисел
        }
    }
}

// MARK: - Future Service Card

struct FutureServiceCard: View {
    let animateText: Bool
    @State private var currentFeatureIndex = 0
    @State private var showDetails = false
    
    private let futureFeatures: [(String, String, String)] = [
        ("🧵", "Стрэнды", "Личные связи с прочностью: растёт от совместных дел, ветшает без них"),
        ("🌉", "Коллективные мосты", "Общие структуры на карте кампуса, построенные вкладом студентов"),
        ("📦", "Курьерские рейсы", "Микроквесты «передай/оцифруй/достань», рейтинг надёжности и благодарности"),
        ("🏠", "Сейфхаусы", "Чек-ин точки (библиотека/кафе) с особыми режимами и быстрым матчингом"),
        ("🗺️", "Следы помощи", "Тепловая карта троп благодарностей и успешно решённых задач"),
        ("🙏", "Цепочки «Спасибо»", "Благодарность каскадом доходит до всех косвенных помощников"),
        ("🎯", "Контракты", "Временные задания с SLA и наградой, матчинг по навыкам/расписанию"),
        ("⚡", "Штормы дедлайнов", "Эвенты с бустами и общими целями вокруг предстоящих сдач"),
        ("🔧", "Модули мостов", "Шумодав, автосводки, анонимные вопросы и другие апгрейды пространств"),
        ("📡", "Маяки", "SOS «нужна помощь рядом сейчас» — одноразовые, быстро затухающие"),
        ("🎒", "Тайники знаний", "Общие кэши материалов с «износом» и автоочисткой слабого контента"),
        ("🧭", "Состыковки расписаний", "Подбор напарников по совпадающим свободным окнам"),
        ("🎮", "Боссфайты", "Кооп-подготовка к экзамену с ролями, прогрессом и «лутом»-бустами"),
        ("🌀", "Асинхронные пары", "90-сек объяснения с автоиндексацией и мгновенным матчингом"),
        ("🪪", "Маски доверия", "Мягкая анонимность новых связей с «раскрытием» по мере сотрудничества")
    ]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "sparkles.rectangle.stack")
                    .font(.title2)
                    .foregroundColor(.orange)
                    .frame(width: 30, height: 30)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Скоро в Connect")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                    
                    Text("Функции для создания связей")
                        .font(.caption)
                        .foregroundColor(.orange.opacity(0.8))
                }
                
                Spacer()
                
                Button(action: {
                    withAnimation(.spring()) {
                        showDetails.toggle()
                    }
                }) {
                    Image(systemName: showDetails ? "chevron.up.circle.fill" : "chevron.down.circle.fill")
                        .font(.title3)
                        .foregroundColor(.orange)
                }
            }
            
            if showDetails {
                VStack(spacing: 12) {
                    ForEach(Array(futureFeatures.enumerated()), id: \.offset) { index, feature in
                        HStack(spacing: 12) {
                            Text(feature.0)
                                .font(.title2)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(feature.1)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(.white)
                                
                                Text(feature.2)
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            
                            Spacer()
                        }
                        .padding(.vertical, 4)
                        .scaleEffect(animateText ? 1.0 : 0.8)
                        .opacity(animateText ? 1.0 : 0.0)
                        .animation(.easeInOut(duration: 0.6).delay(0.1 * Double(index)), value: animateText)
                    }
                }
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.8).combined(with: .opacity),
                    removal: .scale(scale: 0.8).combined(with: .opacity)
                ))
            } else {
                // Краткое превью одной функции с автопрокруткой
                HStack(spacing: 12) {
                    Text(futureFeatures[currentFeatureIndex].0)
                        .font(.title2)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(futureFeatures[currentFeatureIndex].1)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                        
                        Text(futureFeatures[currentFeatureIndex].2)
                            .font(.caption)
                            .foregroundColor(.gray)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    
                    Spacer()
                }
                .padding(.vertical, 4)
                .onAppear {
                    startFeatureRotation()
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(
                    LinearGradient(
                        colors: [.orange.opacity(0.05), .black.opacity(0.8)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(
                            LinearGradient(
                                colors: [.orange.opacity(0.3), .clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
        )
        .scaleEffect(animateText ? 1.0 : 0.9)
        .opacity(animateText ? 1.0 : 0.0)
        .animation(.easeInOut(duration: 0.8).delay(0.6), value: animateText)
    }
    
    private func startFeatureRotation() {
        Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { _ in
            withAnimation(.easeInOut(duration: 0.5)) {
                currentFeatureIndex = (currentFeatureIndex + 1) % futureFeatures.count
            }
        }
    }
}

// MARK: - Connection Status Component

struct ConnectionStatusCard: View {
    let status: ConnectService.ConnectionStatus
    let animateText: Bool
    @State private var pulseAnimation = false
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: status.icon)
                .font(.title3)
                .foregroundColor(status.color)
                .scaleEffect(pulseAnimation ? 1.2 : 1.0)
                .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: pulseAnimation)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Статус сети")
                    .font(.caption)
                    .foregroundColor(.gray)
                
                Text(status.description)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .lineLimit(2)
            }
            
            Spacer()
        }
        .padding(16)
        .background(
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [status.color.opacity(0.1), .black.opacity(0.8)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .overlay(
                    Capsule()
                        .stroke(
                            status.color.opacity(0.3),
                            lineWidth: 1
                        )
                )
        )
        .scaleEffect(animateText ? 1.0 : 0.9)
        .opacity(animateText ? 1.0 : 0.0)
        .animation(.easeInOut(duration: 0.8).delay(0.4), value: animateText)
        .onAppear {
            pulseAnimation = true
        }
    }
}

// MARK: - Easter Egg Components

struct KojimaEasterEggView: View {
    @Binding var isPresented: Bool
    @State private var animateText = false
    @State private var animateGlow = false
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.9)
                .ignoresSafeArea()
                .onTapGesture {
                    isPresented = false
                }
            
            VStack(spacing: 30) {
                // Kojima logo effect
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [.yellow, .orange, .red, .black],
                                center: .center,
                                startRadius: 20,
                                endRadius: 100
                            )
                        )
                        .frame(width: 200, height: 200)
                        .scaleEffect(animateGlow ? 1.2 : 0.8)
                        .opacity(animateGlow ? 0.8 : 0.6)
                    
                    VStack {
                        Image(systemName: "gamecontroller.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.white)
                            .shadow(color: .yellow, radius: 10)
                        
                        Text("🎆")
                            .font(.system(size: 40))
                    }
                }
                .animation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true), value: animateGlow)
                
                VStack(spacing: 20) {
                    Text("ХИДЕО КОДЗИМА")
                        .font(.system(size: 32, weight: .black, design: .default))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.yellow, .orange, .red],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .shadow(color: .orange, radius: 10)
                        .scaleEffect(animateText ? 1.1 : 0.9)
                    
                    Text("ГЕНИЙ!!!")
                        .font(.system(size: 48, weight: .black, design: .default))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.white, .yellow, .orange],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .shadow(color: .yellow, radius: 15)
                        .scaleEffect(animateText ? 1.2 : 1.0)
                    
                    Text("Мастер создания связей между мирами")
                        .font(.system(size: 16, weight: .medium, design: .monospaced))
                        .foregroundColor(.cyan)
                        .opacity(animateText ? 1.0 : 0.7)
                }
                .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: animateText)
                
                Text("Нажмите чтобы продолжить строить мосты")
                    .font(.caption)
                    .foregroundColor(.gray)
                    .opacity(0.8)
            }
        }
        .onAppear {
            animateText = true
            animateGlow = true
        }
    }
}

#Preview {
    ConnectTab(currentUser: User(name: "Test", facultyId: "1", facultyName: "Test", groupId: "1", groupName: "Test"), isInSplitView: false)
}
