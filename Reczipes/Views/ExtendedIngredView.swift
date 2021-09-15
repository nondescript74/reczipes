//
//  ExtendedIngredView.swift
//  ZTester4
//
//  Created by Zahirudeen Premji on 11/22/20.
//

import SwiftUI

struct ExtendedIngredView: View {
    
    // MARK: - Initializer
    init(extendedIngredient: ExtendedIngredient) {
        self.myExtIngredient = extendedIngredient
    }
    // MARK: - Properties
    fileprivate var myExtIngredient: ExtendedIngredient!

    // MARK: - Methods
    fileprivate func getMetaInfo(meta: [String?]?) -> String {
        var myReturnMetaInfo: String = ""
        if !meta!.isEmpty {
            for item in meta! {
                myReturnMetaInfo += item!
                myReturnMetaInfo += ", "
            }
        }
        return myReturnMetaInfo
    }
    // MARK: - View Process
    var body: some View {
        VStack(alignment: .leading) {
            ImageAndNameView(extendedIngredient: myExtIngredient)
            MeasuresView(measures: myExtIngredient.measures ?? Measures.measuresExample)
            Text(getMetaInfo(meta: myExtIngredient.metaInformation))
        }
    }
}

struct ImageAndNameView: View {
    // MARK: - Initializer
    init(extendedIngredient: ExtendedIngredient) {
        self.myExtIngredient = extendedIngredient
    }
    // MARK: - Properties
    fileprivate var myExtIngredient: ExtendedIngredient!
    private enum msgs: String {
        case noIngredName = "No Ingredient Name??"
    }
    // MARK: Methods
    // MARK: - View Process
    var body: some View {
        HStack(alignment: .center) {
            ImageWithSectionItemView(extendedIngredient: myExtIngredient)
                Spacer()
            Text(myExtIngredient.name ?? msgs.noIngredName.rawValue)
                .font(.headline)
                //.foregroundColor(.blue)
                .padding()
        }
    }
}

struct MeasureView: View {
    // MARK: - Initializer
    init(measure: Measure) {
        self.myMeasure = measure
    }
    // MARK: - Properties
    fileprivate var myMeasure: Measure!
    private enum msgs: String {
        case noAmount = "No amount??"
        case noUnitShort = "No unitShort??"
        case noUnitLong = "No unitLong??"
    }
    var body: some View {
        HStack(alignment: .top) {
            Text(myMeasure.amount?.description ?? msgs.noAmount.rawValue)
            Text(myMeasure.unitLong ?? msgs.noUnitLong.rawValue)
        }
    }
}

struct MeasuresView: View {
    // MARK: - Initializer
    init(measures: Measures) {
        self.myMeasures = measures
    }
    // MARK: - Properties
    fileprivate var myMeasures: Measures!
    // MARK: - View Process
    var body: some View {
        HStack {
            Text(myMeasures.us?.amount?.description ?? "0") + Text(" ") + Text(myMeasures.us?.unitLong ?? "pounds?") + Text(" or")
            Text(myMeasures.metric?.amount?.description ?? "0") + Text(" ") + Text(myMeasures.metric?.unitLong ?? "kilos?")
        }.edgesIgnoringSafeArea(.all)
    }
}

#if DEBUG
struct MeasuresView_Previews: PreviewProvider {
    static let myExtendedIngredient: ExtendedIngredient = ExtendedIngredient.extendedIngredientExample
    static var previews: some View {
        Group {
            //MeasureView(measure: Measure.measureExampleUS)
            //MeasuresView(measures: Measures.measuresExample)
            ExtendedIngredView(extendedIngredient: myExtendedIngredient)
        }
    }
}
#endif