import SwiftUI

/// Weather screen built on WeatherKit through the existing provider.
struct WeatherScreen: View {
    struct City: Identifiable {
        let id = UUID()
        let name: String
        let latitude: Double
        let longitude: Double
    }

    private let cities = [
        City(name: "Київ", latitude: 50.4501, longitude: 30.5234),
        City(name: "Львів", latitude: 49.8397, longitude: 24.0297),
        City(name: "Одеса", latitude: 46.4825, longitude: 30.7233)
    ]

    @Environment(\.dismiss) private var dismiss
    @State private var selectedIndex = 0
    @State private var snapshot: WeatherSnapshot?
    @State private var isLoading = false
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Picker("Місто", selection: $selectedIndex) {
                        ForEach(cities.indices, id: \.self) { index in
                            Text(cities[index].name).tag(index)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)

                    if isLoading {
                        ProgressView().padding(40)
                    } else if let snapshot {
                        currentCard(snapshot)
                        hourlyCard(snapshot)
                        dailyCard(snapshot)
                    } else if let errorText {
                        Text(errorText)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding()
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("Погода")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Закрити") { dismiss() } }
            }
            .task(id: selectedIndex) { await load() }
        }
    }

    private func currentCard(_ snapshot: WeatherSnapshot) -> some View {
        VStack(spacing: 8) {
            Image(systemName: snapshot.current.symbolName)
                .font(.system(size: 56))
                .symbolRenderingMode(.multicolor)
            Text("\(Int(snapshot.current.temperatureCelsius.rounded()))°")
                .font(.system(size: 56, weight: .thin, design: .rounded))
            Text(snapshot.current.condition)
                .font(.headline)
            Text("Відчувається як \(Int(snapshot.current.apparentTemperatureCelsius.rounded()))°")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .padding(.horizontal)
    }

    private func hourlyCard(_ snapshot: WeatherSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Найближчі години").font(.headline)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 18) {
                    ForEach(Array(snapshot.hourly.prefix(12).enumerated()), id: \.offset) { _, hour in
                        VStack(spacing: 6) {
                            Text(hour.date.formatted(.dateTime.hour()))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Image(systemName: hour.symbolName)
                                .symbolRenderingMode(.multicolor)
                            Text("\(Int(hour.temperatureCelsius.rounded()))°")
                                .font(.callout.weight(.medium))
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(.horizontal)
    }

    private func dailyCard(_ snapshot: WeatherSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("На кілька днів").font(.headline)
            ForEach(Array(snapshot.daily.prefix(7).enumerated()), id: \.offset) { _, day in
                HStack {
                    Text(day.date.formatted(.dateTime.weekday(.wide)))
                        .font(.callout)
                    Spacer()
                    Image(systemName: day.symbolName).symbolRenderingMode(.multicolor)
                    Text("\(Int(day.lowTemperatureCelsius.rounded()))° / \(Int(day.highTemperatureCelsius.rounded()))°")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(.horizontal)
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        let target = cities[min(selectedIndex, cities.count - 1)]
        let sample = LocationSample(
            latitude: target.latitude,
            longitude: target.longitude,
            horizontalAccuracy: 0,
            timestamp: Date(),
            speed: -1,
            course: -1,
            source: .manual
        )
        let location = ValidatedLocation(
            sample: sample,
            quality: .precise,
            isSafeForLocationActions: true,
            manualLabel: target.name
        )
        do {
            let snapshot = try await WeatherContextEngine(provider: AppleWeatherKitProvider())
                .weather(for: WeatherRequest(location: location, context: .manualLocation))
            self.snapshot = snapshot
            errorText = nil
        } catch {
            errorText = "Не вдалося отримати погоду: \(error)"
            self.snapshot = nil
        }
    }
}
