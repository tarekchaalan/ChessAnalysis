import CoreData
import Foundation
import Combine

final class PersistenceController {
    static let shared = PersistenceController()

    let container: NSPersistentContainer

    init(inMemory: Bool = false) {
        let model = NSManagedObjectModel()
        let (gameEntity, analysisEntity) = Self.makeEntities()
        model.entities = [gameEntity, analysisEntity]

        container = NSPersistentContainer(name: "ChessAnalysis", managedObjectModel: model)
        if inMemory {
            container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
        }
        container.loadPersistentStores { _, error in
            if let error {
                fatalError("Failed to load store: \(error)")
            }
        }
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }

    private static func makeEntities() -> (NSEntityDescription, NSEntityDescription) {
        let entity = NSEntityDescription()
        entity.name = "GameEntity"
        entity.managedObjectClassName = NSStringFromClass(GameEntity.self)

        let id = NSAttributeDescription()
        id.name = "id"
        id.attributeType = .UUIDAttributeType
        id.isOptional = false

        let remoteId = NSAttributeDescription()
        remoteId.name = "remoteId"
        remoteId.attributeType = .stringAttributeType
        remoteId.isOptional = false

        let pgnPath = NSAttributeDescription()
        pgnPath.name = "pgnPath"
        pgnPath.attributeType = .stringAttributeType
        pgnPath.isOptional = false

        let downloadedAt = NSAttributeDescription()
        downloadedAt.name = "downloadedAt"
        downloadedAt.attributeType = .dateAttributeType
        downloadedAt.isOptional = false

        let lastAnalyzedAt = NSAttributeDescription()
        lastAnalyzedAt.name = "lastAnalyzedAt"
        lastAnalyzedAt.attributeType = .dateAttributeType
        lastAnalyzedAt.isOptional = true

        let analysisVersion = NSAttributeDescription()
        analysisVersion.name = "analysisVersion"
        analysisVersion.attributeType = .integer32AttributeType
        analysisVersion.isOptional = false

        let bytesOnDisk = NSAttributeDescription()
        bytesOnDisk.name = "bytesOnDisk"
        bytesOnDisk.attributeType = .integer64AttributeType
        bytesOnDisk.isOptional = false

        entity.properties = [
            id,
            remoteId,
            pgnPath,
            downloadedAt,
            lastAnalyzedAt,
            analysisVersion,
            bytesOnDisk
        ]
        let analysisEntity = NSEntityDescription()
        analysisEntity.name = "MoveAnalysisEntity"
        analysisEntity.managedObjectClassName = NSStringFromClass(MoveAnalysisEntity.self)

        let ply = NSAttributeDescription()
        ply.name = "ply"
        ply.attributeType = .integer32AttributeType
        ply.isOptional = false

        let fen = NSAttributeDescription()
        fen.name = "fen"
        fen.attributeType = .stringAttributeType
        fen.isOptional = false

        let playedUci = NSAttributeDescription()
        playedUci.name = "playedUci"
        playedUci.attributeType = .stringAttributeType
        playedUci.isOptional = false

        let bestUci = NSAttributeDescription()
        bestUci.name = "bestUci"
        bestUci.attributeType = .stringAttributeType
        bestUci.isOptional = false

        let evalBefore = NSAttributeDescription()
        evalBefore.name = "evalBefore"
        evalBefore.attributeType = .integer32AttributeType
        evalBefore.isOptional = false

        let evalAfter = NSAttributeDescription()
        evalAfter.name = "evalAfter"
        evalAfter.attributeType = .integer32AttributeType
        evalAfter.isOptional = false

        let loss = NSAttributeDescription()
        loss.name = "loss"
        loss.attributeType = .integer32AttributeType
        loss.isOptional = false

        let classification = NSAttributeDescription()
        classification.name = "classification"
        classification.attributeType = .stringAttributeType
        classification.isOptional = false

        let pv = NSAttributeDescription()
        pv.name = "pv"
        pv.attributeType = .stringAttributeType
        pv.isOptional = true

        let game = NSRelationshipDescription()
        game.name = "game"
        game.destinationEntity = entity
        game.minCount = 1
        game.maxCount = 1
        game.deleteRule = .nullifyDeleteRule

        let analyses = NSRelationshipDescription()
        analyses.name = "analyses"
        analyses.destinationEntity = analysisEntity
        analyses.minCount = 0
        analyses.maxCount = 0
        analyses.deleteRule = .cascadeDeleteRule

        game.inverseRelationship = analyses
        analyses.inverseRelationship = game

        analysisEntity.properties = [
            ply,
            fen,
            playedUci,
            bestUci,
            evalBefore,
            evalAfter,
            loss,
            classification,
            pv,
            game
        ]
        entity.properties.append(analyses)
        return (entity, analysisEntity)
    }
}

@objc(GameEntity)
final class GameEntity: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var remoteId: String
    @NSManaged var pgnPath: String
    @NSManaged var downloadedAt: Date
    @NSManaged var lastAnalyzedAt: Date?
    @NSManaged var analysisVersion: Int32
    @NSManaged var bytesOnDisk: Int64
    @NSManaged var analyses: Set<MoveAnalysisEntity>?
}

@objc(MoveAnalysisEntity)
final class MoveAnalysisEntity: NSManagedObject {
    @NSManaged var ply: Int32
    @NSManaged var fen: String
    @NSManaged var playedUci: String
    @NSManaged var bestUci: String
    @NSManaged var evalBefore: Int32
    @NSManaged var evalAfter: Int32
    @NSManaged var loss: Int32
    @NSManaged var classification: String
    @NSManaged var pv: String?
    @NSManaged var game: GameEntity
}
