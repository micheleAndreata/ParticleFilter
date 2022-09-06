//
//  ParticleFilter.swift
//  ParticleFilter
//
//  Created by Michele Andreata on 27/07/22.
//
import Foundation

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
    
    public init(_ numParticles: Int, _ wall: Wall) {
        self.numParticles = numParticles
        self.wall = wall
    }
    
    public func predictPosition(_ arPosition: Point) -> ApproximatedPosition {
        // TODO: cambiare std prima pos
        let firstPosStd = Point(x: 0.8, y: 0.8)
        
        if self.lastPredictionTime == -1 {
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
        
        return self.estimatePosition()
    }
    
    public func initializeDistribution(firstPosition firstPos: Point,  firstPositionStd firstPosStd: Point) {
        for idx in 0..<self.numParticles {
            let sampleX = gaussianDistribution(mean: firstPos.x, deviation: firstPosStd.x)
            let sampleY = gaussianDistribution(mean: firstPos.y, deviation: firstPosStd.y)
            let newParticle = Particle(id: idx, p: Point(x: sampleX, y: sampleY), weight: 1)
            self.particles.append(newParticle)
        }
        self.isInitialized = true
    }
    
    /*
     * prende ogni particella e la sposta a caso nei dintorni di dove stava prima
     * con velocità massima di 1 m/s
     * sceglie un angolo a caso con distribuzione uniforme su 0 - 360
     * sceglie una velocità a caso con distribuzione uniforme su 0 - 1 m/s
     * fai spostare la particella in quella direzione
     * se il segmento di spostamento intercetta il muro particella si ferma dove i due segmenti si intercettano
     */
    public func transitionModel(deltaT dt: Double) {
        for idx in 0..<self.numParticles {
            let oldPos = self.particles[idx].p
            let velocity = Double.random(in: 0 ..< 1)
            let angle = Double.random(in: 0 ..< 2 * Double.pi)
            let newXPos = oldPos.x + velocity * dt * cos(angle)
            let newYPos = oldPos.y + velocity * dt * sin(angle)
            let newPos = Point(x: newXPos, y: newYPos)
            var i: Point?
            if getIntersection(newPos, oldPos, self.wall.from, self.wall.to, intersection: &i) {
                self.particles[idx].p = i!
            }
            else {
                self.particles[idx].p = newPos
            }
        }
    }
    
    /*
     * aggiorna per ogni particella il suo peso a 1/(distanza da arPosition)
     */
    public func perceptionModel(_ arPos: Point) {
        for idx in 0..<self.numParticles {
            let distance = distance(self.particles[idx].p, arPos)
            self.particles[idx].weight = 1 / distance
        }
    }
    
    /*
     * Resample particles with replacement with probability proportional to weight
     * TODO: una certa percentuale di particelle andrebbero create randomicamente (es 1% ogni secondo)
     *       attorno alla posizione data da AR ignorando le particelle precedenti
     */
    public func resample() {
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
        for _ in particlesCopy {
            particles.append(particlesCopy[weightsDist.draw()])
        }
    }
    
    /*
     * cicla su tutte le particelle e calcola la media pesata di x e y --> questo è il baricentro
     * ordina particelle sulla base della loro distanza dal baricentro
     * prendi paticella x% più lontana dal baricentro (es 90%) e prendi distanza di quella particella dal baricentro
     * ritorna baricentro come pos e distanza come raggio
     */
    public func estimatePosition() -> ApproximatedPosition {
        let cogX = (self.particles.reduce(0.0, {$0 + $1.p.x})) / Double(self.particles.count)
        let cogY = (self.particles.reduce(0.0, {$0 + $1.p.y})) / Double(self.particles.count)
        let centerOfGravity = Point(x: cogX, y: cogY)
        
        let distances = self.particles.map{($0.id, distance($0.p, centerOfGravity))}
        let sortedDistances = distances.sorted(by: {$0.1>$1.1})
        
        let idx = Int(floor(0.9*Double(self.particles.count)))
        let radius = sortedDistances[idx].1

        return ApproximatedPosition(position: centerOfGravity, approximationRadius: radius)
    }
}

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
