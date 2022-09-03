//
//  File.swift
//  
//
//  Created by Michele Andreata on 03/09/22.
//

import Foundation

public struct Point {
    var x: Double
    var y: Double
}

public struct Particle {
    var id: Int
    var p: Point
    var weight: Double
}

public struct ApproximatedPosition {
    var position: Point
    var approximationRadius: Double
}

public struct Wall {
    var from: Point
    var to: Point
}

/*
 * Gaussian Distribution using the Box-Muller Transformation
 */
func gaussianDistribution(mean: Double, deviation: Double) -> Double {
    guard deviation > 0 else { return mean }
    
    let x1 = Double.random(in: 0 ..< 1)
    let x2 = Double.random(in: 0 ..< 1)
    let z1 = sqrt(-2 * log(x1)) * cos(2 * Double.pi * x2) // z1 is normally distributed
    
    // Convert z1 from the Standard Normal Distribution to Normal Distribution
    return z1 * deviation + mean
}

/*
 * Random number distribution that produces integer values according to a discrete distribution
 * It works the same as in: https://cplusplus.com/reference/random/discrete_distribution/
 */
class DiscreteDistribution {
    private var cumsum: [Double]
    
    init(weights w: [Double]) {
        let sum = w.reduce(0) {$0+$1}
        let probDist = w.map {$0 / sum}
        self.cumsum = (probDist.reduce(into: [0.0]) { $0.append($0.last! + $1) }).dropLast(1)
    }
    
    func draw() -> Int {
        let r = Double.random(in: 0..<1)
        var idx = 0
        for i in 0..<self.cumsum.count {
            if r > self.cumsum[i] {
                idx = i
            }
            else {
                break
            }
        }
        return idx
    }
}

/*
 * Returns true if the lines intercept, otherwise false. In addition, if they intersect, the
 * intersection point is stored in Point i
 * Readapted for swift from:
 * https://stackoverflow.com/questions/563198/how-do-you-detect-where-two-line-segments-intersect/#1968345
 */
func getIntersection(_ p0: Point,_ p1: Point,_ p2: Point,_ p3: Point,intersection i: inout Point?) -> Bool {
    let s1 = Point(x: (p1.x - p0.x), y: (p1.y - p0.y))
    let s2 = Point(x: (p3.x - p2.x), y: (p3.y - p2.y))
    
    let s = (-s1.y * (p0.x - p2.x) + s1.x * (p0.y - p2.y)) / (-s2.x * s1.y + s1.x * s2.y)
    let t = ( s2.x * (p0.y - p2.y) - s2.y * (p0.x - p2.x)) / (-s2.x * s1.y + s1.x * s2.y)
    
    if (s >= 0 && s <= 1 && t >= 0 && t <= 1) {
        i = Point(x: p0.x + (t * s1.x), y: p0.y + (t * s1.y))
        return true
    }
    return false
}

func distance(_ p1: Point,_ p2: Point) -> Double {
    return sqrt((p1.x - p2.x)*(p1.x - p2.x) + (p1.y - p2.y)*(p1.y - p2.y))
}
