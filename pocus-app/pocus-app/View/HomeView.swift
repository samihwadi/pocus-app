import SwiftUI
import FamilyControls

struct HomeView: View {
    @ObservedObject var viewModel: HomeViewModel  // Pass viewModel instead of creating a new one
    @State private var showSettings: Bool = false
    @State private var animateGradient: Bool = false

    private let startColor: Color = .black
    private let endColor: Color = .gray

    var body: some View {
        NavigationView {
            VStack {
                HStack {
                    Spacer()
                    Button(action: {
                        showSettings.toggle()
                    }) {
                        Image(systemName: "gearshape")
                            .foregroundColor(.white)
                            .padding()
                    }
                    .sheet(isPresented: $showSettings) {
                        SettingsView(timerValue: $viewModel.settings.initialTimerValue,
                                     breakValue: $viewModel.settings.initialBreakValue,
                                     totalCycles: $viewModel.settings.totalCycles)
                            .onDisappear {
                                viewModel.applySettings()
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
                        .trim(from: 0.0, to: viewModel.progress)
                        .stroke(Color.green, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 300, height: 300)
                        .animation(.linear(duration: 1), value: viewModel.progress)

                    Button(action: {
                        viewModel.handleButtonPress()
                    }) {
                        VStack {
                            Text(viewModel.isBreak ? "Break" : "Stay Focused")
                                .font(.custom("SFProDisplay-Regular", size: 24))
                                .foregroundColor(.white)

                            Text(viewModel.timerString)
                                .font(.custom("SFProDisplay-Regular", size: 24))
                                .foregroundColor(.white)

                            Text("Round \(viewModel.currentCycle)")
                                .font(.custom("SFProDisplay-Regular", size: 16))
                                .foregroundColor(.white.opacity(0.7))
                        }
                        .frame(width: 180, height: 180)
                        .background(Color.clear)
                        .cornerRadius(90)
                    }
                }

                Spacer()

                Button("Select Apps to Block") {
                    viewModel.isPickerPresented = true
                }
                .familyActivityPicker(isPresented: $viewModel.isPickerPresented, selection: $viewModel.selectedApps)
                .foregroundColor(.white)
            }
            .onAppear {
                viewModel.resumeTimer() // Ensures timer runs even after backgrounding
               
            }
           

            .background(LinearGradient(colors: [startColor, endColor], startPoint: .topLeading, endPoint: .bottomTrailing)
                .edgesIgnoringSafeArea(.all))
        }
    }
}
