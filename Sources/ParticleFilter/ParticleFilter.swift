//
//  ParticleFilter.swift
//  ParticleFilter
//
//  Created by Michele Andreata on 27/07/22.
//
import Foundation

let MAX_PARTICLE_VELOCITY = 200.0
let DEFAULT_POSITION_STD = Point(x: 30, y: 30)
let RAND_RESAMPLE_PERCENTAGE = 0.01
let RAND_RESAMPLE_INTERVAL = 1.0

public class ParticleFilter {
    // time istant of the last prediction
    var lastPredictionTime = -1.0
    
    // Number of particles to draw
    var numParticles: Int
    
    // Flag, if filter is initialized
    var isInitialized = false
    
    //  Set of current particles
    var particles = [Particle]()
    
    var wall: Wall
    
    private var approxPos = ApproximatedPosition(position: Point(x: 0, y: 0), approximationRadius: 0)
    
    private var randomResampling = false
    
    public init(_ numParticles: Int, _ wall: Wall) {
        self.numParticles = numParticles
        self.wall = wall
        if #available(iOS 10.0, *) {
            let _ = Timer.scheduledTimer(withTimeInterval: RAND_RESAMPLE_INTERVAL, repeats: true) { _ in
                self.randomResampling = true
            }
        } else {
            // Fallback on earlier versions
            Timer.scheduledTimer(
                timeInterval: RAND_RESAMPLE_INTERVAL,
                target: self,
                selector: #selector(self.doRandResample),
                userInfo: nil, repeats: true)
        }
    }
    
    @objc private func doRandResample() {
        self.randomResampling = true
    }
    
    public func predictPosition(_ arPosition: Point) -> ApproximatedPosition {
        let firstPosStd = DEFAULT_POSITION_STD
        
        if self.lastPredictionTime == -1 {
            self.approxPos = ApproximatedPosition(position: arPosition, approximationRadius: 15)
            self.initializeDistribution(firstPosition: arPosition, firstPositionStd: firstPosStd)
            self.lastPredictionTime = Date().timeIntervalSince1970
        }
        else {
            let currentLastPredTime = Date().timeIntervalSince1970
            let dt = currentLastPredTime - self.lastPredictionTime
            self.lastPredictionTime = currentLastPredTime
            transitionModel(deltaT: dt)
        }
        
        self.perceptionModel(arPosition)
        
        self.resample()
        
        self.approxPos = self.estimatePosition()
        
        return self.approxPos
    }
    
    /*
     * Initializes particle filter by initializing particles to Gaussian
     * distribution around first position and all the weights set to 1
     */
    private func initializeDistribution(firstPosition firstPos: Point,  firstPositionStd firstPosStd: Point) {
        for idx in 0..<self.numParticles {
            let sampleX = gaussianDistribution(mean: firstPos.x, deviation: firstPosStd.x)
            let sampleY = gaussianDistribution(mean: firstPos.y, deviation: firstPosStd.y)
            let newParticle = Particle(id: idx, p: Point(x: sampleX, y: sampleY), weight: 1)
            self.particles.append(newParticle)
        }
        self.isInitialized = true
    }
    
    /*
     * chooses an angle randomly with uniform distribution on [0, 360]
     * chooses a velocity randomly with uniform ditribution on [0, MAX_PARTICLE_VELOCITY]
     * moves the particle in that direction
     * if displacement segment intercepts the wall, particle stops where the two segments intersect
     */
    private func transitionModel(deltaT dt: Double) {
        for idx in 0..<self.numParticles {
            let oldPos = self.particles[idx].p
            let velocity = Double.random(in: 0 ..< MAX_PARTICLE_VELOCITY)
            let angle = Double.random(in: 0 ..< 2 * Double.pi)
            let newXPos = oldPos.x + velocity * dt * cos(angle)
            let newYPos = oldPos.y + velocity * dt * sin(angle)
            let newPos = Point(x: newXPos, y: newYPos)
            var int: Point?
            if getIntersection(newPos, oldPos, self.wall.from, self.wall.to, intersection: &int) {
                // The intersection is not exactly on the wall but a little bit behind. I choose
                // 90% of the distance between the old position and the intersection on the wall.
                // Segment parametrization taken from:
                // https://math.stackexchange.com/questions/134112/find-a-point-on-a-line-segment-located-at-a-distance-d-from-one-endpoint#134135
//                let d = 0.9*distance(oldPos, int!)
//                let denominator = sqrt((oldPos.x - int!.x)*(oldPos.x - int!.x) + (oldPos.y - int!.y)*(oldPos.y - int!.y))
//                if denominator == 0 {
//                    self.particles[idx].p = int!
//                    print("zero den")
//                }
//                else {
//                    let quasiIntX = oldPos.x + (d*(int!.x - oldPos.x) / denominator)
//                    let quasiIntY = oldPos.y + (d*(int!.y - oldPos.y) / denominator)
//    //                print(Point(x: quasiIntX, y: quasiIntY))
//                    self.particles[idx].p = Point(x: quasiIntX, y: quasiIntY)
//                }
                self.particles[idx].p = oldPos
            }
            else {
                self.particles[idx].p = newPos
            }
        }
    }
    
    private func perceptionModel(_ arPos: Point) {
        for idx in 0..<self.numParticles {
            let distance = distance(self.particles[idx].p, arPos)
            self.particles[idx].weight = 1 / (distance)
        }
    }
    
    /*
     * Resample particles with replacement with probability proportional to weight
     */
    private func resample() {
        let particlesCopy = self.particles
        self.particles.removeAll()
        
        var weights = [Double]()
        for p in particlesCopy {
            weights.append(p.weight)
        }
        
        let weightsDist = DiscreteDistribution(weights: weights)
        
        // With the discrete distribution pick out particles according to their
        // weights. The higher the weight of the particle, the higher are the chances
        // of the particle being included multiple times.
        // It also resamples randomly a percentage (RAND_RESAMPLE_PERCENTAGE) of the
        // particles every RAND_RESAMPLE_INTERVAL seconds
        if self.randomResampling {
            let partialNumPart = Int(floor((1 - RAND_RESAMPLE_PERCENTAGE)*Double(particlesCopy.count)))
            let arPosStd = DEFAULT_POSITION_STD
            for i in 0..<partialNumPart {
                var p = particlesCopy[weightsDist.draw()]
                p.id = i
                self.particles.append(p)
            }
            for i in partialNumPart..<particlesCopy.count {
                let randX = gaussianDistribution(mean: self.approxPos.position.x, deviation: arPosStd.x)
                let randY = gaussianDistribution(mean: self.approxPos.position.y, deviation: arPosStd.y)
                let randomParticle = Particle(id: i, p: Point(x: randX, y: randY), weight: 1.0)
                self.particles.append(randomParticle)
            }
            self.randomResampling = false
        }
        else {
            for i in 0..<particlesCopy.count {
                var p = particlesCopy[weightsDist.draw()]
                p.id = i
                particles.append(p)
            }
        }
    }
    
    public func estimatePosition() -> ApproximatedPosition {
        let cogX = (self.particles.reduce(0.0, {$0 + $1.p.x})) / Double(self.particles.count)
        let cogY = (self.particles.reduce(0.0, {$0 + $1.p.y})) / Double(self.particles.count)
        let centerOfGravity = Point(x: cogX, y: cogY)
        
        let distances = self.particles.map{distance($0.p, centerOfGravity)}
        let sortedDistances = distances.sorted(by: {$0<$1})
        
        let idx = Int(floor(0.9*Double(self.particles.count)))
        let radius = sortedDistances[idx]

        return ApproximatedPosition(position: centerOfGravity, approximationRadius: radius)
    }
}

public struct Point {
    var x: Double
    var y: Double
}

public struct Particle: Identifiable {
    public var id: Int
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
