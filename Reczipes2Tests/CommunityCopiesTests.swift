//
//  CommunityCopiesTests.swift
//  Reczipes2Tests
//
//  Shared-list copies collapse only when title AND ingredient names match.
//

import Testing
import Foundation
@testable import Reczipes2

@Suite("Community copies")
@MainActor
struct CommunityCopiesTests {
    @Test("Case, accents and punctuation don't make two copies different")
    func normalizedMatch() {
        let a = CommunityCopies.signature(title: "Crème Caramel!", ingredientNames: ["Sugar", "Eggs", "Milk"])
        let b = CommunityCopies.signature(title: "creme  caramel", ingredientNames: ["milk", "eggs", "sugar"])
        #expect(a == b)
    }

    @Test("Same title with different ingredients stays apart")
    func titleIsNotIdentity() {
        let a = CommunityCopies.signature(title: "Soups", ingredientNames: ["lentils", "onion"])
        let b = CommunityCopies.signature(title: "Soups", ingredientNames: ["chicken", "onion"])
        #expect(a != b)
    }

    @Test("Normalising matches the web rule")
    func normalized() {
        #expect(CommunityCopies.normalized("  Pho Gà (Chicken-Noodle) ") == "pho ga chicken noodle")
    }
}
