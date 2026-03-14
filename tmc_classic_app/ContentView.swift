import SwiftUI
import Combine

// MARK: - Models

struct Player: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var hcpIndex: Double
    
    init(name: String, hcpIndex: Double) {
        self.id = UUID()
        self.name = name
        self.hcpIndex = hcpIndex
    }
    
    func courseHcp(slope: Double) -> Int {
        Int(Foundation.round(hcpIndex * (slope / 113.0)))
    }
}

struct Team: Identifiable, Codable {
    let id: UUID
    var name: String
    var colorName: String
    var playerIDs: [UUID]
    var points: Double
    
    init(name: String, colorName: String, playerIDs: [UUID]) {
        self.id = UUID()
        self.name = name
        self.colorName = colorName
        self.playerIDs = playerIDs
        self.points = 0
    }
}

struct Course: Codable {
    var name: String
    var slope: Double
    var rating: Double
    var par: Int
    
    static var empty: Course { Course(name: "", slope: 113, rating: 72.0, par: 72) }
}

enum GameFormat: String, CaseIterable, Codable {
    case bestBall = "Best Ball"
    case scramble = "Scramble"
    case matchPlay = "Match Play"
    case stableford = "Stableford"
}

struct TourneyRound: Identifiable, Codable {
    let id: UUID
    var format: GameFormat
    var matchups: [[UUID]]
    var course: Course
    var completed: Bool
    
    init(format: GameFormat, matchups: [[UUID]], course: Course = .empty) {
        self.id = UUID()
        self.format = format
        self.matchups = matchups
        self.course = course
        self.completed = false
    }
}

// MARK: - View Model

class TournamentVM: ObservableObject {
    @Published var players: [Player] = []
    @Published var teams: [Team] = []
    @Published var rounds: [TourneyRound] = []
    @Published var scores: [Int: [UUID: [Int: Int]]] = [:]
    @Published var setupStep = 1
    @Published var started = false
    @Published var currentRound = 0
    @Published var currentHole = 1
    
    let teamColors = ["green", "blue", "gold", "pink"]
    let teamNames = ["Green", "Blue", "Gold", "Pink"]
    
    func addPlayer(name: String, hcp: Double) {
        guard !name.isEmpty, hcp >= 0, hcp <= 54 else { return }
        guard !players.contains(where: { $0.name.lowercased() == name.lowercased() }) else { return }
        players.append(Player(name: name, hcpIndex: hcp))
        teams = []
        rounds = []
    }
    
    func removePlayer(_ p: Player) {
        players.removeAll { $0.id == p.id }
        teams = []
        rounds = []
    }
    
    func canProceedFromStep1() -> Bool {
        players.count >= 4 && players.count % 2 == 0
    }
    
    func generateTeams() {
        let sorted = players.sorted { $0.hcpIndex < $1.hcpIndex }
        let half = sorted.count / 2
        let low = Array(sorted[0..<half]).shuffled()
        let high = Array(sorted[half...]).shuffled()
        teams = []
        for i in 0..<low.count {
            let t = Team(
                name: "Team \(teamNames[i % teamNames.count])",
                colorName: teamColors[i % teamColors.count],
                playerIDs: [low[i].id, high[i].id]
            )
            teams.append(t)
        }
    }
    
    func randomizeGames() {
        let formats = GameFormat.allCases.shuffled()
        let matchups = roundRobin(teamIDs: teams.map { $0.id })
        rounds = []
        for i in 0..<formats.count {
            let r = TourneyRound(format: formats[i], matchups: matchups[i % matchups.count])
            rounds.append(r)
        }
    }
    
    private func roundRobin(teamIDs: [UUID]) -> [[[UUID]]] {
        var t = teamIDs
        if t.count % 2 != 0 { t.append(UUID()) }
        let n = t.count
        var allRounds: [[[UUID]]] = []
        for _ in 0..<(n - 1) {
            var pairs: [[UUID]] = []
            for i in 0..<(n / 2) {
                let t1 = t[i]
                let t2 = t[n - 1 - i]
                if teamIDs.contains(t1) && teamIDs.contains(t2) {
                    pairs.append([t1, t2])
                }
            }
            allRounds.append(pairs)
            let last = t.removeLast()
            t.insert(last, at: 1)
        }
        return allRounds
    }
    
    func startTournament() {
        scores = [:]
        for r in 0..<4 {
            scores[r] = [:]
            for p in players {
                scores[r]![p.id] = [:]
                for h in 1...18 {
                    scores[r]![p.id]![h] = 0
                }
            }
        }
        started = true
    }
    
    func getScore(roundIdx: Int, player: UUID, hole: Int) -> Int {
        return scores[roundIdx]?[player]?[hole] ?? 0
    }
    
    func setScore(roundIdx: Int, player: UUID, hole: Int, val: Int) {
        let v = max(0, min(15, val))
        scores[roundIdx]?[player]?[hole] = v
    }
    
    func adjustScore(roundIdx: Int, player: UUID, hole: Int, delta: Int) {
        let cur = getScore(roundIdx: roundIdx, player: player, hole: hole)
        setScore(roundIdx: roundIdx, player: player, hole: hole, val: cur + delta)
    }
    
    func allHolesFilled(roundIdx: Int) -> Bool {
        for p in players {
            for h in 1...18 {
                if getScore(roundIdx: roundIdx, player: p.id, hole: h) <= 0 { return false }
            }
        }
        return true
    }
    
    func holeFilled(roundIdx: Int, hole: Int) -> Bool {
        for p in players {
            if getScore(roundIdx: roundIdx, player: p.id, hole: hole) <= 0 { return false }
        }
        return true
    }
    
    func completeRound(_ r: Int) {
        rounds[r].completed = true
        calcTeamPoints()
    }
    
    func playerByID(_ pid: UUID) -> Player? { players.first { $0.id == pid } }
    func teamByID(_ tid: UUID) -> Team? { teams.first { $0.id == tid } }
    func teamForPlayer(_ pid: UUID) -> Team? { teams.first { $0.playerIDs.contains(pid) } }
    
    func teamColor(_ t: Team) -> Color {
        switch t.colorName {
        case "green": return .green
        case "blue": return .blue
        case "gold": return .yellow
        case "pink": return .pink
        default: return .gray
        }
    }
    
    func teamColorByID(_ tid: UUID) -> Color {
        guard let t = teamByID(tid) else { return .gray }
        return teamColor(t)
    }
    
    func parPerHole(roundIdx: Int) -> Int {
        return Int(Foundation.round(Double(rounds[roundIdx].course.par) / 18.0))
    }
    
    func calcMatchResult(roundIdx: Int, t1id: UUID, t2id: UUID) -> (t1wins: Int, t2wins: Int) {
        guard let t1 = teamByID(t1id), let t2 = teamByID(t2id) else { return (0, 0) }
        let fmt = rounds[roundIdx].format
        let par = parPerHole(roundIdx: roundIdx)
        var w1 = 0
        var w2 = 0
        
        for h in 1...18 {
            switch fmt {
            case .bestBall, .scramble:
                let s1 = t1.playerIDs.compactMap { pid -> Int? in
                    let s = getScore(roundIdx: roundIdx, player: pid, hole: h)
                    return s > 0 ? s : nil
                }.min() ?? 99
                let s2 = t2.playerIDs.compactMap { pid -> Int? in
                    let s = getScore(roundIdx: roundIdx, player: pid, hole: h)
                    return s > 0 ? s : nil
                }.min() ?? 99
                if s1 < s2 { w1 += 1 } else if s2 < s1 { w2 += 1 }
                
            case .matchPlay:
                var s1 = 0
                var s2 = 0
                for pid in t1.playerIDs { s1 += getScore(roundIdx: roundIdx, player: pid, hole: h) }
                for pid in t2.playerIDs { s2 += getScore(roundIdx: roundIdx, player: pid, hole: h) }
                if s1 < s2 { w1 += 1 } else if s2 < s1 { w2 += 1 }
                
            case .stableford:
                var s1 = 0
                var s2 = 0
                for pid in t1.playerIDs { s1 += stablefordPts(getScore(roundIdx: roundIdx, player: pid, hole: h), par) }
                for pid in t2.playerIDs { s2 += stablefordPts(getScore(roundIdx: roundIdx, player: pid, hole: h), par) }
                if s1 > s2 { w1 += 1 } else if s2 > s1 { w2 += 1 }
            }
        }
        return (w1, w2)
    }
    
    func stablefordPts(_ score: Int, _ par: Int) -> Int {
        guard score > 0 else { return 0 }
        let d = score - par
        if d <= -2 { return 4 }
        if d == -1 { return 3 }
        if d == 0 { return 2 }
        if d == 1 { return 1 }
        return 0
    }
    
    func calcTeamPoints() {
        for i in 0..<teams.count { teams[i].points = 0 }
        for r in 0..<rounds.count {
            guard rounds[r].completed else { continue }
            for m in rounds[r].matchups {
                let res = calcMatchResult(roundIdx: r, t1id: m[0], t2id: m[1])
                guard let i1 = teams.firstIndex(where: { $0.id == m[0] }),
                      let i2 = teams.firstIndex(where: { $0.id == m[1] }) else { continue }
                if res.t1wins == res.t2wins {
                    teams[i1].points += 0.5
                    teams[i2].points += 0.5
                } else if res.t1wins > res.t2wins {
                    teams[i1].points += 1
                } else {
                    teams[i2].points += 1
                }
            }
        }
    }
    
    func quotaPts(_ score: Int, _ par: Int) -> Int {
        guard score > 0 else { return 0 }
        let d = score - par
        if d <= -2 { return 4 }
        if d == -1 { return 2 }
        if d == 0 { return 1 }
        return 0
    }
    
    func calcQuota(playerID: UUID) -> (totalDiff: Int, roundsPlayed: Int) {
        guard let p = playerByID(playerID) else { return (0, 0) }
        var total = 0
        var played = 0
        for r in 0..<rounds.count {
            let par = parPerHole(roundIdx: r)
            var rPts = 0
            var has = false
            for h in 1...18 {
                let sc = getScore(roundIdx: r, player: playerID, hole: h)
                if sc > 0 {
                    has = true
                    rPts += quotaPts(sc, par)
                }
            }
            if has {
                let chcp = p.courseHcp(slope: rounds[r].course.slope)
                total += rPts - chcp
                played += 1
            }
        }
        return (total, played)
    }
    
    func scoreName(_ score: Int, _ par: Int) -> String {
        let d = score - par
        if d <= -3 { return "Albatross!" }
        if d == -2 { return "Eagle!" }
        if d == -1 { return "Birdie" }
        if d == 0 { return "Par" }
        if d == 1 { return "Bogey" }
        if d == 2 { return "Double" }
        return "+\(d)"
    }
    
    func scoreColor(_ score: Int, _ par: Int) -> Color {
        guard score > 0 else { return .gray }
        let d = score - par
        if d <= -2 { return .yellow }
        if d == -1 { return .green }
        if d == 0 { return .white }
        if d == 1 { return .orange }
        return .red
    }
}

// MARK: - Main App View

struct ContentView: View {
    @StateObject private var vm = TournamentVM()
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            SetupView(vm: vm, selectedTab: $selectedTab)
                .tabItem { Label("Setup", systemImage: "gearshape.fill") }
                .tag(0)
            ScheduleView(vm: vm)
                .tabItem { Label("Schedule", systemImage: "calendar") }
                .tag(1)
            ScoringView(vm: vm)
                .tabItem { Label("Scoring", systemImage: "figure.golf") }
                .tag(2)
            LeaderboardView(vm: vm)
                .tabItem { Label("Leaders", systemImage: "trophy.fill") }
                .tag(3)
        }
        .preferredColorScheme(.dark)
        .tint(.green)
    }
}

// MARK: - Setup View

struct SetupView: View {
    @ObservedObject var vm: TournamentVM
    @Binding var selectedTab: Int
    @State private var pName = ""
    @State private var pHcp = ""
    @FocusState private var nameFieldFocused: Bool
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    stepIndicator

                    if vm.setupStep == 1 {
                        step1Players
                    } else if vm.setupStep == 2 {
                        step2Teams
                    } else if vm.setupStep == 3 {
                        step3Games
                    } else {
                        step4Courses
                    }
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .contentMargins(.bottom, 100, for: .scrollContent)
            .background(Color(red: 0.04, green: 0.1, blue: 0.06))
            .navigationTitle("⛳ TMC Classic")
        }
    }
    
    var stepIndicator: some View {
        HStack(spacing: 0) {
            ForEach(1..<5) { s in
                Circle()
                    .fill(s < vm.setupStep ? Color.green : Color.clear)
                    .overlay(Circle().stroke(s <= vm.setupStep ? Color.green : Color.gray, lineWidth: 2))
                    .overlay(
                        Text("\(s)")
                            .font(.caption.bold())
                            .foregroundColor(s < vm.setupStep ? .black : s == vm.setupStep ? .green : .gray)
                    )
                    .frame(width: 30, height: 30)
                if s < 4 {
                    Rectangle()
                        .fill(s < vm.setupStep ? Color.green : Color.gray.opacity(0.3))
                        .frame(height: 2)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.bottom, 8)
    }
    
    var step1Players: some View {
        VStack(spacing: 12) {
            CardView(title: "👥 Add Players") {
                Text("Add 4-8 players with GHIN handicap index. Need an even number.")
                    .font(.caption).foregroundColor(.gray)
                
                ForEach(vm.players) { p in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(p.name).font(.headline)
                            Text("HCP Index: \(p.hcpIndex, specifier: "%.1f")")
                                .font(.caption).foregroundColor(.green.opacity(0.7))
                        }
                        Spacer()
                        Button(action: { vm.removePlayer(p) }) {
                            Image(systemName: "xmark.circle.fill").foregroundColor(.red)
                        }
                    }
                    .padding(10)
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(10)
                }
                
                HStack(spacing: 8) {
                    TextField("Name", text: $pName)
                        .textFieldStyle(.roundedBorder)
                        .focused($nameFieldFocused)
                        .onSubmit { addP() }
                    TextField("HCP", text: $pHcp)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.decimalPad)
                        .frame(width: 70)
                        .onSubmit { addP() }
                    Button(action: { addP() }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2).foregroundColor(.green)
                    }
                }
            }
            
            Button(action: {
                if vm.teams.isEmpty { vm.generateTeams() }
                vm.setupStep = 2
            }) {
                Text(vm.canProceedFromStep1()
                     ? "Next: Generate Teams →"
                     : "Need \(max(0, 4 - vm.players.count)) more players")
                    .frame(maxWidth: .infinity).padding()
                    .background(vm.canProceedFromStep1() ? Color.green : Color.gray)
                    .foregroundColor(.black).bold().cornerRadius(14)
            }
            .disabled(!vm.canProceedFromStep1())
        }
        .onAppear { nameFieldFocused = true }
    }
    
    func addP() {
        guard let h = Double(pHcp) else { return }
        vm.addPlayer(name: pName, hcp: h)
        pName = ""
        pHcp = ""
        nameFieldFocused = true
    }
    
    var step2Teams: some View {
        VStack(spacing: 12) {
            CardView(title: "🎲 Randomized Teams") {
                Text("Low handicap paired with high. Same teams all tournament.")
                    .font(.caption).foregroundColor(.gray)
                ForEach(vm.teams) { t in
                    TeamRowView(vm: vm, team: t)
                }
            }
            
            Button(action: { vm.generateTeams() }) {
                Label("Re-Randomize", systemImage: "dice.fill")
                    .frame(maxWidth: .infinity).padding()
                    .background(Color.green.opacity(0.15)).foregroundColor(.green)
                    .cornerRadius(14)
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.green, lineWidth: 2))
            }
            
            Button(action: {
                if vm.rounds.isEmpty { vm.randomizeGames() }
                vm.setupStep = 3
            }) {
                Text("Lock Teams & Continue →")
                    .frame(maxWidth: .infinity).padding()
                    .background(Color.green).foregroundColor(.black).bold().cornerRadius(14)
            }
            
            Button(action: { vm.setupStep = 1 }) {
                Text("← Back to Players").font(.caption).foregroundColor(.green)
            }
        }
    }
    
    var step3Games: some View {
        VStack(spacing: 12) {
            CardView(title: "🎯 Randomized Games") {
                Text("4 formats in random order with round-robin matchups.")
                    .font(.caption).foregroundColor(.gray)
                ForEach(0..<vm.rounds.count, id: \.self) { i in
                    RoundPreviewRow(vm: vm, index: i, rnd: vm.rounds[i])
                }
            }
            
            Button(action: { vm.randomizeGames() }) {
                Label("Re-Randomize", systemImage: "dice.fill")
                    .frame(maxWidth: .infinity).padding()
                    .background(Color.green.opacity(0.15)).foregroundColor(.green)
                    .cornerRadius(14)
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.green, lineWidth: 2))
            }
            
            Button(action: { vm.setupStep = 4 }) {
                Text("Lock Schedule & Set Courses →")
                    .frame(maxWidth: .infinity).padding()
                    .background(Color.green).foregroundColor(.black).bold().cornerRadius(14)
            }
            
            Button(action: { vm.setupStep = 2 }) {
                Text("← Back to Teams").font(.caption).foregroundColor(.green)
            }
        }
    }
    
    var step4Courses: some View {
        VStack(spacing: 12) {
            Text("⛳ Set Course per Round").font(.headline).foregroundColor(.green)
            Text("Enter course details. Handicaps recalculate per course slope.")
                .font(.caption).foregroundColor(.gray)
            ForEach(0..<vm.rounds.count, id: \.self) { i in
                CourseFormRow(vm: vm, roundIdx: i)
            }

            let allNamed = vm.rounds.allSatisfy { !$0.course.name.isEmpty }
            Button(action: {
                vm.startTournament()
                selectedTab = 1
            }) {
                Text("🏆 Start Tournament")
                    .frame(maxWidth: .infinity).padding()
                    .background(allNamed ? Color.green : Color.gray)
                    .foregroundColor(.black).bold().cornerRadius(14)
            }
            .disabled(!allNamed)

            Button(action: { vm.setupStep = 3 }) {
                Text("← Back to Schedule").font(.caption).foregroundColor(.green)
            }
        }
    }
}

// MARK: - Reusable Sub Views

struct CardView<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline).foregroundColor(.green)
            content()
        }
        .padding()
        .background(Color.white.opacity(0.05))
        .cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.green.opacity(0.2)))
    }
}

struct TeamRowView: View {
    @ObservedObject var vm: TournamentVM
    let team: Team
    
    var body: some View {
        HStack {
            RoundedRectangle(cornerRadius: 2)
                .fill(vm.teamColor(team))
                .frame(width: 4, height: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(team.name).font(.subheadline.bold()).foregroundColor(vm.teamColor(team))
                let names = team.playerIDs.compactMap { vm.playerByID($0)?.name }.joined(separator: " & ")
                Text(names).font(.caption).foregroundColor(.gray)
            }
            Spacer()
        }
        .padding(10)
        .background(Color.white.opacity(0.05))
        .cornerRadius(10)
    }
}

struct RoundPreviewRow: View {
    @ObservedObject var vm: TournamentVM
    let index: Int
    let rnd: TourneyRound
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(rnd.format.rawValue).font(.caption.bold()).foregroundColor(.green)
                Spacer()
                Text("Round \(index + 1)")
                    .font(.caption2).padding(.horizontal, 8).padding(.vertical, 2)
                    .background(Color.blue.opacity(0.2)).cornerRadius(8).foregroundColor(.blue)
            }
            ForEach(rnd.matchups, id: \.self) { m in
                if let t1 = vm.teamByID(m[0]), let t2 = vm.teamByID(m[1]) {
                    HStack(spacing: 4) {
                        Text(t1.name).foregroundColor(vm.teamColor(t1))
                        Text("vs").foregroundColor(.gray)
                        Text(t2.name).foregroundColor(vm.teamColor(t2))
                    }.font(.caption)
                }
            }
        }
        .padding(10)
        .background(Color.white.opacity(0.05))
        .cornerRadius(10)
    }
}

struct CourseFormRow: View {
    @ObservedObject var vm: TournamentVM
    let roundIdx: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Round \(roundIdx + 1): \(vm.rounds[roundIdx].format.rawValue)")
                .font(.caption.bold()).foregroundColor(.green)
            TextField("Course name", text: $vm.rounds[roundIdx].course.name)
                .padding(8)
                .background(Color(.systemGray6))
                .cornerRadius(8)
            HStack(spacing: 8) {
                VStack(alignment: .leading) {
                    Text("Slope").font(.caption2).foregroundColor(.gray)
                    TextField("113", value: $vm.rounds[roundIdx].course.slope, format: .number)
                        .keyboardType(.decimalPad)
                        .padding(8)
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                }
                VStack(alignment: .leading) {
                    Text("Rating").font(.caption2).foregroundColor(.gray)
                    TextField("72", value: $vm.rounds[roundIdx].course.rating, format: .number)
                        .keyboardType(.decimalPad)
                        .padding(8)
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                }
                VStack(alignment: .leading) {
                    Text("Par").font(.caption2).foregroundColor(.gray)
                    TextField("72", value: $vm.rounds[roundIdx].course.par, format: .number)
                        .keyboardType(.numberPad)
                        .padding(8)
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                }
            }
        }
        .padding(10)
        .background(Color.white.opacity(0.03))
        .cornerRadius(10)
    }
}

// MARK: - Schedule View

struct ScheduleView: View {
    @ObservedObject var vm: TournamentVM

    var body: some View {
        NavigationView {
            ZStack {
                Color(red: 0.04, green: 0.1, blue: 0.06).ignoresSafeArea()
                ScrollView {
                    if !vm.started && vm.teams.isEmpty {
                        scheduleEmptyState
                    } else {
                        scheduleContent
                    }
                }
            }
            .navigationTitle("📅 Schedule")
        }
    }

    private var scheduleEmptyState: some View {
        VStack(spacing: 8) {
            Text("📋").font(.system(size: 48))
            Text("Set up tournament first").foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var scheduleContent: some View {
        VStack(spacing: 16) {
            scheduleTeamsSection
            Divider().background(Color.green.opacity(0.3))
            scheduleRoundsSection
        }
        .padding()
    }

    private var scheduleTeamsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("👥 Teams").font(.headline).foregroundColor(.green)
            ForEach(vm.teams) { t in
                ScheduleTeamRow(vm: vm, team: t)
            }
        }
    }

    private var scheduleRoundsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("📅 Rounds").font(.headline).foregroundColor(.green)
            ForEach(0..<vm.rounds.count, id: \.self) { i in
                ScheduleRoundCard(vm: vm, index: i)
            }
        }
    }
}

struct ScheduleTeamRow: View {
    @ObservedObject var vm: TournamentVM
    let team: Team

    var body: some View {
        HStack {
            RoundedRectangle(cornerRadius: 2)
                .fill(vm.teamColor(team))
                .frame(width: 4, height: 40)
            VStack(alignment: .leading) {
                Text(team.name).font(.subheadline.bold()).foregroundColor(vm.teamColor(team))
                let info = team.playerIDs.compactMap { pid -> String? in
                    guard let p = vm.playerByID(pid) else { return nil }
                    return "\(p.name) (HCP \(String(format: "%.1f", p.hcpIndex)))"
                }.joined(separator: " · ")
                Text(info).font(.caption).foregroundColor(.gray)
            }
            Spacer()
        }
        .padding(10)
        .background(Color.white.opacity(0.05))
        .cornerRadius(10)
    }
}

struct ScheduleRoundCard: View {
    @ObservedObject var vm: TournamentVM
    let index: Int
    
    var body: some View {
        let rnd = vm.rounds[index]
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(rnd.format.rawValue).font(.caption.bold()).foregroundColor(.green)
                Spacer()
                Text(rnd.completed ? "✅ Done" : "Round \(index + 1)")
                    .font(.caption2).padding(.horizontal, 8).padding(.vertical, 2)
                    .background(rnd.completed ? Color.green.opacity(0.2) : Color.blue.opacity(0.2))
                    .cornerRadius(8)
                    .foregroundColor(rnd.completed ? .green : .blue)
            }
            if !rnd.course.name.isEmpty {
                Text("⛳ \(rnd.course.name)").font(.subheadline.bold())
                Text("Slope \(rnd.course.slope, specifier: "%.0f") · Rating \(rnd.course.rating, specifier: "%.1f") · Par \(rnd.course.par)")
                    .font(.caption).foregroundColor(.gray)
            }
            ForEach(rnd.matchups, id: \.self) { m in
                if let t1 = vm.teamByID(m[0]), let t2 = vm.teamByID(m[1]) {
                    HStack(spacing: 4) {
                        Text(t1.name).foregroundColor(vm.teamColor(t1))
                        Text("vs").foregroundColor(.gray)
                        Text(t2.name).foregroundColor(vm.teamColor(t2))
                    }.font(.caption)
                }
            }
            let hcps = vm.players.map { "\($0.name): \($0.courseHcp(slope: rnd.course.slope))" }.joined(separator: ", ")
            Text("Course HCPs: \(hcps)").font(.caption2).foregroundColor(.gray.opacity(0.7))
        }
        .padding(12)
        .background(Color.white.opacity(0.05))
        .cornerRadius(12)
    }
}

// MARK: - Scoring View

struct ScoringView: View {
    @ObservedObject var vm: TournamentVM
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if !vm.started {
                    VStack(spacing: 8) {
                        Text("🏌️").font(.system(size: 48))
                        Text("Start tournament first").foregroundColor(.gray)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    // Round picker
                    HStack(spacing: 4) {
                        ForEach(0..<4, id: \.self) { r in
                            Button(action: {
                                vm.currentRound = r
                                vm.currentHole = 1
                            }) {
                                Text("R\(r + 1)")
                                    .font(.caption.bold())
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(r == vm.currentRound ? Color.green : Color.white.opacity(0.05))
                                    .foregroundColor(r == vm.currentRound ? .black : .gray)
                                    .cornerRadius(8)
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                    
                    ScrollView {
                        ScoringContent(vm: vm)
                            .padding()
                    }
                }
            }
            .background(Color(red: 0.04, green: 0.1, blue: 0.06))
            .navigationTitle("🏌️ Scoring")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct ScoringContent: View {
    @ObservedObject var vm: TournamentVM
    
    var body: some View {
        let r = vm.currentRound
        let rnd = vm.rounds[r]
        let par = vm.parPerHole(roundIdx: r)
        
        VStack(spacing: 12) {
            Text("\(rnd.format.rawValue) — \(rnd.course.name)")
                .font(.caption.bold()).foregroundColor(.green.opacity(0.7))
            
            // Hole nav
            HStack {
                Button(action: { if vm.currentHole > 1 { vm.currentHole -= 1 } }) {
                    Image(systemName: "chevron.left.circle.fill").font(.title)
                }.disabled(vm.currentHole <= 1)
                
                Spacer()
                VStack {
                    Text("Hole \(vm.currentHole)").font(.title.bold())
                    Text("Par \(par)").font(.caption).foregroundColor(.gray)
                }
                Spacer()
                
                Button(action: { if vm.currentHole < 18 { vm.currentHole += 1 } }) {
                    Image(systemName: "chevron.right.circle.fill").font(.title)
                }.disabled(vm.currentHole >= 18)
            }
            
            ForEach(rnd.matchups, id: \.self) { m in
                if let t1 = vm.teamByID(m[0]), let t2 = vm.teamByID(m[1]) {
                    Text("\(t1.name) vs \(t2.name)")
                        .font(.caption2.bold()).foregroundColor(.gray).textCase(.uppercase)
                    
                    let allP = t1.playerIDs + t2.playerIDs
                    ForEach(allP, id: \.self) { pid in
                        ScoreRowView(vm: vm, playerID: pid, roundIdx: r, par: par)
                    }
                }
            }
            
            // Hole dots
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 9), spacing: 4) {
                ForEach(1..<19, id: \.self) { h in
                    let filled = vm.holeFilled(roundIdx: r, hole: h)
                    Button(action: { vm.currentHole = h }) {
                        Text("\(h)").font(.caption2.bold())
                            .frame(width: 28, height: 28)
                            .background(h == vm.currentHole ? Color.green : filled ? Color.white.opacity(0.1) : Color.clear)
                            .foregroundColor(h == vm.currentHole ? .black : filled ? .white : .gray)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(filled ? Color.green : Color.gray.opacity(0.3), lineWidth: 1))
                    }
                }
            }.padding(.top, 8)
            
            if vm.allHolesFilled(roundIdx: r) && !rnd.completed {
                Button(action: { vm.completeRound(r) }) {
                    Text("✅ Complete Round \(r + 1)")
                        .frame(maxWidth: .infinity).padding()
                        .background(Color.green).foregroundColor(.black).bold().cornerRadius(14)
                }
            } else if rnd.completed {
                Text("✅ Round Complete").foregroundColor(.green).bold()
            }
        }
    }
}

struct ScoreRowView: View {
    @ObservedObject var vm: TournamentVM
    let playerID: UUID
    let roundIdx: Int
    let par: Int
    
    var body: some View {
        guard let p = vm.playerByID(playerID),
              let team = vm.teamForPlayer(playerID) else { return AnyView(EmptyView()) }
        
        let score = vm.getScore(roundIdx: roundIdx, player: playerID, hole: vm.currentHole)
        let chcp = p.courseHcp(slope: vm.rounds[roundIdx].course.slope)
        
        return AnyView(
            VStack(spacing: 6) {
                HStack {
                    Text(p.name).font(.subheadline.bold()).foregroundColor(vm.teamColor(team))
                    Spacer()
                    Text("CHCP \(chcp)").font(.caption2).foregroundColor(.gray)
                }
                HStack(spacing: 20) {
                    Button(action: { vm.adjustScore(roundIdx: roundIdx, player: playerID, hole: vm.currentHole, delta: -1) }) {
                        Image(systemName: "minus.circle.fill").font(.title)
                    }
                    Text(score > 0 ? "\(score)" : "-")
                        .font(.title.bold())
                        .foregroundColor(score > 0 ? vm.scoreColor(score, par) : .gray)
                        .frame(width: 50)
                    Button(action: { vm.adjustScore(roundIdx: roundIdx, player: playerID, hole: vm.currentHole, delta: 1) }) {
                        Image(systemName: "plus.circle.fill").font(.title)
                    }
                }
                if score > 0 {
                    Text(vm.scoreName(score, par)).font(.caption).foregroundColor(.gray)
                }
            }
            .padding(12)
            .background(Color.white.opacity(0.05))
            .cornerRadius(12)
        )
    }
}

// MARK: - Leaderboard View

struct LeaderboardView: View {
    @ObservedObject var vm: TournamentVM
    @State private var tab = 0
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if !vm.started {
                    VStack(spacing: 8) {
                        Text("🏆").font(.system(size: 48))
                        Text("Start tournament first").foregroundColor(.gray)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Picker("", selection: $tab) {
                        Text("Team Game").tag(0)
                        Text("MVP / Quota").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .padding()
                    
                    ScrollView {
                        if tab == 0 {
                            TeamLeaderboardContent(vm: vm)
                        } else {
                            MVPLeaderboardContent(vm: vm)
                        }
                    }
                }
            }
            .background(Color(red: 0.04, green: 0.1, blue: 0.06))
            .navigationTitle("🏆 Leaderboard")
        }
    }
}

struct TeamLeaderboardContent: View {
    @ObservedObject var vm: TournamentVM
    
    var body: some View {
        let _ = vm.calcTeamPoints()
        let sorted = vm.teams.sorted { $0.points > $1.points }
        let trophies = ["🥇", "🥈", "🥉", ""]
        
        VStack(alignment: .leading, spacing: 8) {
            Text("Team Standings").font(.headline).foregroundColor(.green)
            
            ForEach(0..<sorted.count, id: \.self) { i in
                let t = sorted[i]
                HStack {
                    Text(t.points > 0 ? trophies[min(i, 3)] : "\(i + 1)")
                        .font(.title2.bold()).frame(width: 36)
                        .foregroundColor(i == 0 && t.points > 0 ? .yellow : .gray)
                    VStack(alignment: .leading) {
                        Text(t.name).font(.subheadline.bold()).foregroundColor(vm.teamColor(t))
                        Text(t.playerIDs.compactMap { vm.playerByID($0)?.name }.joined(separator: " & "))
                            .font(.caption).foregroundColor(.gray)
                    }
                    Spacer()
                    Text(String(format: "%.1f", t.points))
                        .font(.title3.bold()).foregroundColor(.green)
                }
                .padding(12)
                .background(i == 0 && t.points > 0 ? Color.yellow.opacity(0.08) : Color.white.opacity(0.05))
                .cornerRadius(12)
                .overlay(
                    i == 0 && t.points > 0
                    ? RoundedRectangle(cornerRadius: 12).stroke(Color.yellow.opacity(0.3))
                    : nil
                )
            }
            
            Divider().background(Color.green.opacity(0.3)).padding(.vertical, 8)
            Text("Round Results").font(.headline).foregroundColor(.green)
            
            ForEach(0..<vm.rounds.count, id: \.self) { r in
                let rnd = vm.rounds[r]
                VStack(alignment: .leading, spacing: 4) {
                    Text("R\(r + 1): \(rnd.format.rawValue) @ \(rnd.course.name)")
                        .font(.caption.bold()).foregroundColor(.green)
                    if !rnd.completed {
                        Text("Not yet played").font(.caption).foregroundColor(.gray)
                    } else {
                        ForEach(rnd.matchups, id: \.self) { m in
                            if let t1 = vm.teamByID(m[0]), let t2 = vm.teamByID(m[1]) {
                                let res = vm.calcMatchResult(roundIdx: r, t1id: m[0], t2id: m[1])
                                let result: String = {
                                    if res.t1wins == res.t2wins { return "Tied — 0.5 pts each" }
                                    if res.t1wins > res.t2wins { return "\(t1.name) wins \(res.t1wins)–\(res.t2wins)" }
                                    return "\(t2.name) wins \(res.t2wins)–\(res.t1wins)"
                                }()
                                Text("\(t1.name) vs \(t2.name): \(result)").font(.caption)
                            }
                        }
                    }
                }
                .padding(12)
                .background(Color.white.opacity(0.05))
                .cornerRadius(12)
            }
        }
        .padding()
    }
}

struct MVPLeaderboardContent: View {
    @ObservedObject var vm: TournamentVM
    
    var body: some View {
        let trophies = ["🥇", "🥈", "🥉", ""]
        let quotaData: [(Player, Int, Int)] = vm.players.map { p in
            let q = vm.calcQuota(playerID: p.id)
            return (p, q.totalDiff, q.roundsPlayed)
        }.sorted { $0.1 > $1.1 }
        
        VStack(alignment: .leading, spacing: 8) {
            Text("MVP — Quota Standings").font(.headline).foregroundColor(.green)
            Text("Eagle=4 · Birdie=2 · Par=1 · Beat your course HCP each round")
                .font(.caption2).foregroundColor(.gray)
            
            ForEach(0..<quotaData.count, id: \.self) { i in
                let p = quotaData[i].0
                let diff = quotaData[i].1
                let played = quotaData[i].2
                
                HStack {
                    Text(played > 0 ? trophies[min(i, 3)] : "\(i + 1)")
                        .font(.title2.bold()).frame(width: 36)
                        .foregroundColor(i == 0 && played > 0 ? .yellow : .gray)
                    VStack(alignment: .leading) {
                        Text(p.name).font(.subheadline.bold())
                        Text("HCP \(p.hcpIndex, specifier: "%.1f") · \(played) round\(played == 1 ? "" : "s")")
                            .font(.caption).foregroundColor(.gray)
                    }
                    Spacer()
                    Text(diff >= 0 ? "+\(diff)" : "\(diff)")
                        .font(.title3.bold())
                        .foregroundColor(diff >= 0 ? .green : .red)
                }
                .padding(12)
                .background(i == 0 && played > 0 ? Color.yellow.opacity(0.08) : Color.white.opacity(0.05))
                .cornerRadius(12)
            }
        }
        .padding()
    }
}

// MARK: - Preview

#Preview {
    ContentView()
}
