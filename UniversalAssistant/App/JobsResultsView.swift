import SwiftUI

struct JobsResultsView: View {
    let jobs: [JobDiscoveryResult]

    var body: some View {
        LazyVStack(spacing: 12) {
            ForEach(jobs) { job in
                VStack(alignment: .leading, spacing: 8) {
                    Text(job.title).font(.headline)
                    Text(job.employer).font(.subheadline.weight(.semibold))
                    if let locality = job.locality { Label(locality, systemImage: "mappin.and.ellipse").font(.subheadline) }
                    if let salary = salary(job) { Text(salary).font(.title3.weight(.bold)).foregroundStyle(.tint) }
                    HStack {
                        Text(job.sourceName).font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Text(job.observedAt, style: .date).font(.caption).foregroundStyle(.secondary)
                    }
                    Link("Відкрити вакансію", destination: job.sourceURL).buttonStyle(.borderedProminent)
                }
                .padding(14)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
        }
        .accessibilityIdentifier("assistant.job-results")
    }

    private func salary(_ job: JobDiscoveryResult) -> String? {
        let currency = job.currency ?? "UAH"
        if let minimum = job.salaryMinimum, let maximum = job.salaryMaximum {
            return "\(minimum)–\(maximum) \(currency)"
        }
        if let minimum = job.salaryMinimum { return "від \(minimum) \(currency)" }
        if let maximum = job.salaryMaximum { return "до \(maximum) \(currency)" }
        return nil
    }
}
