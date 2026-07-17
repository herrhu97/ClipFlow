import Foundation

struct SensitiveContentFilter {
    func shouldIgnore(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        if trimmed.range(of: #"^\d{4,8}$"#, options: .regularExpression) != nil {
            return true
        }
        if trimmed.range(
            of: #"(?i)(password|passwd|passcode|one[- ]?time code|verification code|验证码)\s*[:=]\s*\S+"#,
            options: .regularExpression
        ) != nil {
            return true
        }
        if trimmed.contains("-----BEGIN PRIVATE KEY-----") || trimmed.contains("-----BEGIN RSA PRIVATE KEY-----") {
            return true
        }

        let digits = trimmed.filter(\.isNumber)
        if (13...19).contains(digits.count), trimmed.allSatisfy({ $0.isNumber || " -".contains($0) }) {
            return isValidLuhnNumber(digits)
        }
        return false
    }

    private func isValidLuhnNumber(_ value: String) -> Bool {
        let numbers = value.reversed().compactMap(\.wholeNumberValue)
        let sum = numbers.enumerated().reduce(0) { result, pair in
            let (index, digit) = pair
            if index.isMultiple(of: 2) { return result + digit }
            let doubled = digit * 2
            return result + (doubled > 9 ? doubled - 9 : doubled)
        }
        return sum.isMultiple(of: 10)
    }
}
