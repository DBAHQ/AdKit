//
//  NumericHelpers.swift
//  AdKit
//
//  Копии расширений приложения, на которые опирается разбор выручки.
//  Держим внутренними, чтобы не конфликтовать с одноимёнными в приложении.
//

import Foundation

extension Decimal {

    func roundedDecimal(to scale: Int, mode: NSDecimalNumber.RoundingMode = .plain) -> Decimal {
        var decimal = self
        var result = Decimal()
        NSDecimalRound(&result, &decimal, scale, mode)
        return result
    }
}

extension Double {

    var decimalValue: Decimal { Decimal(self) }
}

extension String {

    var decimal: Decimal? {
        let numberString = replacingOccurrences(of: ",", with: ".").replacingOccurrences(of: " ", with: "")
        return Decimal(string: numberString)?.roundedDecimal(to: 8) ?? 0
    }
}
