import SwiftUI

struct SettingsView: View {
    @Binding var timerValue: Int
    @Binding var breakValue: Int
    @Binding var totalCycles: Int

    var body: some View {
        VStack {
            Text("Settings")
                .font(.custom("SFProDisplay-Regular", size: 24))
                .padding()

            Form {
                Section(header: Text("Work Duration")) {
                    Stepper(value: $timerValue, in: 60...3600, step: 60) {
                        Text("\(timerValue / 60) minutes")
                    }
                }

                Section(header: Text("Break Duration")) {
                    Stepper(value: $breakValue, in: 60...1800, step: 60) {
                        Text("\(breakValue / 60) minutes")
                    }
                }

                Section(header: Text("Number of Cycles")) {
                    Stepper(value: $totalCycles, in: 1...10) {
                        Text("\(totalCycles) cycles")
                    }
                }
            }
            .font(.custom("SFProDisplay-Regular", size: 18))
        }
        .padding()
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView(timerValue: .constant(1500), breakValue: .constant(300), totalCycles: .constant(4))
    }
}
