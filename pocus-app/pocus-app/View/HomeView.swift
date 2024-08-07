import SwiftUI
import Combine

struct HomeView: View {
    @State private var initialTimerValue: Int = 1500 // Default 25 minutes in seconds
    @State private var initialBreakValue: Int = 300  // Default 5 minutes in seconds
    @State private var timerValue: Int = 1500 // Default 25 minutes in seconds
    @State private var breakValue: Int = 300  // Default 5 minutes in seconds
    @State private var timerRunning: Bool = false
    @State private var timer: AnyCancellable?
    @State private var progress: CGFloat = 0.0
    @State private var currentCycle: Int = 1
    @State private var totalCycles: Int = 4 // Default 4 cycles
    @State private var showSettings: Bool = false
    @State private var isBreak: Bool = false
    @State private var buttonPressCount: Int = 0
    @State private var lastPressTime: Date = Date()

    @State private var animateGradient: Bool = false
    
    private let startColor: Color = .black
    private let endColor: Color = .gray

    var body: some View {
        NavigationView {
            VStack {
                HStack {
                    Spacer()
                    Button(action: {
                        self.showSettings.toggle()
                    }) {
                        Image(systemName: "gearshape")
                            .foregroundColor(.white)
                            .padding()
                    }
                    .sheet(isPresented: $showSettings) {
                        SettingsView(timerValue: $initialTimerValue, breakValue: $initialBreakValue, totalCycles: $totalCycles)
                            .onDisappear {
                                self.applySettings()
                            }
                    }
                }
                HStack {
                    VStack(alignment: .leading) {
                        Text("Block Out All")
                            .font(.custom("SFProDisplay-Regular", size: 30))
                            .foregroundColor(.white)
                        
                        Text("Distractions")
                            .font(.custom("SFProDisplay-Regular", size: 30))
                            .foregroundColor(.white)
                        
                        Divider()
                            .frame(height: 2)
                            .background(Color.white)
                            .padding(.top, -10)
                            .padding(.trailing, 200)
                    }
                    .padding(.leading, 20)
                    
                    Spacer()
                }
                
                Spacer()

                ZStack {
                    Circle()
                        .stroke(Color.gray.opacity(0.3), lineWidth: 5)
                        .frame(width: 300, height: 300)

                    Circle()
                        .trim(from: 0.0, to: progress)
                        .stroke(Color.green, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 300, height: 300)
                        .animation(.linear(duration: 1), value: progress)

                    Button(action: {
                        self.handleButtonPress()
                    }) {
                        VStack {
                            Text(isBreak ? "Break" : "Stay Focused")
                                .font(.custom("SFProDisplay-Regular", size: 24))
                                .foregroundColor(.white)

                            Text(timerString(time: isBreak ? breakValue : timerValue))
                                .font(.custom("SFProDisplay-Regular", size: 24))
                                .foregroundColor(.white)

                            Text("Round \(currentCycle)")
                                .font(.custom("SFProDisplay-Regular", size: 16))
                                .foregroundColor(.white.opacity(0.7))
                        }
                        .frame(width: 180, height: 180)
                        .background(Color.clear)
                        .cornerRadius(90)
                    }
                }

                Spacer()

                HStack {
                    Spacer()
                    Text("Cycles: \(totalCycles)")
                        .font(.custom("SFProDisplay-Regular", size: 16))
                        .foregroundColor(.white.opacity(0.7))
                        .padding()
                }
            }
            .frame(maxWidth: .infinity)
            .foregroundColor(.black)
            .padding(.horizontal)
            .multilineTextAlignment(.center)
            .background {
                LinearGradient(colors: [startColor, endColor], startPoint: .topLeading, endPoint: .bottomTrailing)
                    .edgesIgnoringSafeArea(.all)
                    .hueRotation(.degrees(animateGradient ? 45 : 0))
                    .onAppear {
                        withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: true)) {
                            animateGradient.toggle()
                        }
                    }
            }
        }
    }

    func handleButtonPress() {
        let currentTime = Date()
        let timeInterval = currentTime.timeIntervalSince(lastPressTime)
        lastPressTime = currentTime

        if timeInterval < 0.5 {
            // Double press detected
            if isBreak {
                self.stopTimer()
                self.isBreak = false
                self.timerValue = initialTimerValue // Reset work duration
                self.startTimer()
            }
        } else {
            // Single press detected
            if !timerRunning {
                self.startTimer()
            } else if isBreak {
                self.stopTimer()
            }
        }
    }

    func timerString(time: Int) -> String {
        let minutes = time / 60
        let seconds = time % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    func startTimer() {
        timerRunning = true
        progress = 0.0
        let totalTime = isBreak ? breakValue : timerValue
        timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect().sink { _ in
            if self.isBreak {
                if self.breakValue > 0 {
                    self.breakValue -= 1
                    withAnimation(.linear(duration: 1.0)) {
                        self.progress = CGFloat(self.initialBreakValue - self.breakValue) / CGFloat(self.initialBreakValue)
                    }
                } else {
                    self.endBreak()
                }
            } else {
                if self.timerValue > 0 {
                    self.timerValue -= 1
                    withAnimation(.linear(duration: 1.0)) {
                        self.progress = CGFloat(self.initialTimerValue - self.timerValue) / CGFloat(self.initialTimerValue)
                    }
                } else {
                    self.endWork()
                }
            }
        }
    }

    func endWork() {
        print("End of work period")
        self.stopTimer()
        if self.currentCycle < self.totalCycles {
            self.isBreak = true
            self.breakValue = initialBreakValue // Reset break duration
            self.startTimer()
        } else {
            // All cycles are complete
            self.timerRunning = false
            self.isBreak = false
            self.progress = 0.0
            self.resetTimerValues()
            print("All cycles complete")
        }
    }

    func endBreak() {
        print("End of break period")
        self.stopTimer()
        self.currentCycle += 1
        if self.currentCycle <= self.totalCycles {
            self.isBreak = false
            self.timerValue = initialTimerValue // Reset work duration
            self.startTimer()
        } else {
            // All cycles are complete
            self.timerRunning = false
            self.isBreak = false
            self.progress = 0.0
            self.resetTimerValues()
            print("All cycles complete")
        }
    }

    func stopTimer() {
        timerRunning = false
        timer?.cancel()
        timer = nil
    }

    func resetTimerValues() {
        self.timerValue = initialTimerValue
        self.breakValue = initialBreakValue
        self.currentCycle = 1
    }

    func applySettings() {
        self.timerValue = initialTimerValue
        self.breakValue = initialBreakValue
        self.progress = 0.0
        self.currentCycle = 1
        self.timerRunning = false
        self.isBreak = false
        self.stopTimer()  // Ensuring timer is stopped when settings are applied
    }
}

struct HomeView_Previews: PreviewProvider {
    static var previews: some View {
        HomeView()
    }
}
