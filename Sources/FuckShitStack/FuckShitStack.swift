//
//  FuckShitStack.swift
//  FuckShitStack
//
//  Created by Jared Sinclair on 7/9/16.
//
// Inspired by Black Pixel's "FuckShitStack" class:
// https://medium.com/bpxl-craft/how-to-add-core-data-to-a-project-89c816ba0384#.wmview7ni

import Foundation
import CoreData
import Etcetera
import os.log

private let CoreDataLog = OSLog(subsystem: "com.niceboy.FuckShitStack", category: "CoreData")

/// A general-purpose Core Data stack using two sibling contexts sharing a
/// common persistent store. The main thread context is intended for read-only
/// use. The background context is for serialized access to read/write operations.
public class FuckShitStack {

    // MARK: Nested Types

    /// The store type.
    public enum StoreType {
        case inMemory
        case sqLite(parentDirectory: URL, storeName: String, recoveryOption: FailedMigrationRecoveryOption)
    }

    /// Other initialization options.
    public enum FailedMigrationRecoveryOption {
        case none
        case nukeAndRetry
    }

    // MARK: Public Properties

    public var mainContext: NSManagedObjectContext {
        return container.viewContext
    }

    // MARK: Private Properties

    private let container: NSPersistentContainer
    private let backgroundQueue: OperationQueue
    private var _backgroundContext = Protected<NSManagedObjectContext?>(nil)

    private var backgroundContext: NSManagedObjectContext {
        assert(backgroundQueue.isCurrent)
        return _backgroundContext.access { context -> NSManagedObjectContext in
            if context == nil {
                context = container.newBackgroundContext()
                context!.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
            }
            return context!
        }
    }

    // MARK: Factory / Init

    public static func new(model: NSManagedObjectModel, storeType: StoreType = .inMemory, completion: @escaping (Result<FuckShitStack, Error>) -> Void) {
        switch storeType {
        case .inMemory:
            do {
                let stack = try newInMemoryStack(model: model)
                completion(.success(stack))
            } catch {
                completion(.failure(error))
            }
        case .sqLite(let parentDirectory, let storeName, let option):
            newSQLiteStack(
                model: model,
                parentDirectory: parentDirectory,
                storeName: storeName,
                recoveryOption: option,
                completion: completion
            )
        }
    }

    public static func newInMemoryStack(model: NSManagedObjectModel) throws -> FuckShitStack {
        let container = NSPersistentContainer(
            name: "FuckShitStack",
            managedObjectModel: model
        )
        let description: NSPersistentStoreDescription = {
            let d = NSPersistentStoreDescription()
            d.type = NSInMemoryStoreType
            d.shouldAddStoreAsynchronously = false
            return d
        }()
        container.persistentStoreDescriptions = [description]
        var error: Error? = nil
        // This callback will be synchronous
        container.loadPersistentStores { (_, e) in
            error = e
        }
        if let error = error {
            throw error
        } else {
            return FuckShitStack(container: container)
        }
    }

    private static func newSQLiteStack(model: NSManagedObjectModel, parentDirectory: URL, storeName: String, recoveryOption: FailedMigrationRecoveryOption, completion: @escaping (Result<FuckShitStack, Error>) -> Void) {

        let storeDirectory = parentDirectory.appendingPathComponent(storeName, isDirectory: true)

        func wipeSubdirectory() {
            _ = FileManager.default.removeFile(at: storeDirectory)
        }

        func createSubdirectory() throws {
            try FileManager.default.createDirectory(
                at: storeDirectory,
                withIntermediateDirectories: true,
                attributes: nil
            )
        }

        func makeContainer(wipeFirst: Bool = false, handler: @escaping (Result<FuckShitStack, Error>) -> Void) {
            if wipeFirst {
                wipeSubdirectory()
            }
            do {
                try createSubdirectory()
            } catch {
                handler(.failure(error))
                return
            }
            let container = NSPersistentContainer(name: "FuckShitStack", managedObjectModel: model)
            let description: NSPersistentStoreDescription = {
                let storeUrl = storeDirectory.appendingPathComponent(storeName, isDirectory: false)
                let d = NSPersistentStoreDescription()
                d.url = storeUrl
                d.type = NSSQLiteStoreType
                d.shouldMigrateStoreAutomatically = true
                d.shouldInferMappingModelAutomatically = true
                d.shouldAddStoreAsynchronously = true
                return d
            }()
            container.persistentStoreDescriptions = [description]
            container.loadPersistentStores { (_, error) in
                if let error = error {
                    handler(.failure(error))
                } else {
                    container.viewContext.mergePolicy = NSMergeByPropertyStoreTrumpMergePolicy
                    container.viewContext.automaticallyMergesChangesFromParent = true
                    let stack = FuckShitStack(container: container)
                    handler(.success(stack))
                }
            }
        }

        func complete(with result: Result<FuckShitStack, Error>) {
            DispatchQueue.main.async {
                completion(result)
            }
        }

        DispatchQueue.global().async {
            makeContainer { firstResult in
                switch firstResult {
                case .success:
                    complete(with: firstResult)
                case .failure:
                    switch recoveryOption {
                    case .none:
                        complete(with: firstResult)
                    case .nukeAndRetry:
                        makeContainer(wipeFirst: true) { secondResult in
                            complete(with: secondResult)
                        }
                    }
                }
            }
        }

    }

    private init(container: NSPersistentContainer) {
        self.container = container
        self.backgroundQueue = {
            let q = OperationQueue()
            q.maxConcurrentOperationCount = 1
            q.qualityOfService = .background
            return q
        }()
        mainContext.automaticallyMergesChangesFromParent = true
    }

    // MARK: Public Methods

    public static func checkIfThereIsStoreAlreadyOnDisk(inParentDirectory directory: URL, storeName: String, completion: @escaping (Result<Bool, Error>) -> Void) {
        let storeDirectory = directory.appendingPathComponent(storeName, isDirectory: true)
        let exists = FileManager.default.fileExists(at: storeDirectory)
        completion(.success(exists))
    }

    public static func moveStore(inParentDirectory oldParent: URL, toNewParentDirectory newParent: URL, storeName: String, completion: @escaping (Result<Void, Error>) -> Void) {
        let oldStoreDirectory = oldParent.appendingPathComponent(storeName, isDirectory: true)
        let newStoreDirectory = newParent.appendingPathComponent(storeName, isDirectory: true)
        do {
            try FileManager.default.moveItem(at: oldStoreDirectory, to: newStoreDirectory)
            completion(.success(()))
        } catch {
            completion(.failure(error))
        }
    }

    public func editInBackground<T: NSManagedObject>(_ object: T, editBlock: @escaping (T, NSManagedObjectContext) -> Void) {
        let task = BackgroundTask.start()
        performInBackground(at: .veryHigh, saveAfterward: true) { (context) in
            let backgroundObject = context.object(with: object.objectID)
            editBlock(backgroundObject as! T, context)
            task?.end()
        }
    }

    public func performInBackground(at priority: Operation.QueuePriority = .normal, saveAfterward: Bool = false, block: @escaping (NSManagedObjectContext) -> Void) {
        let task = BackgroundTask.start()
        let op = BlockOperation { [weak self] in
            guard let this = self else { return }
            let context = this.backgroundContext
            context.performAndWait {
                block(context)
                if saveAfterward {
                    do {
                        try context.save()
                    } catch {
                        CoreDataLog.error(error)
                    }
                }
                task?.end()
            }
        }
        op.queuePriority = priority
        backgroundQueue.addOperation(op)
    }

    public func sync_performInBackground(_ block: @escaping (NSManagedObjectContext) -> Void) {
        let op = BlockOperation { [weak self] in
            guard let this = self else { return }
            let context = this.backgroundContext
            this.backgroundContext.performAndWait {
                block(context)
            }
        }
        op.queuePriority = .veryHigh
        backgroundQueue.addOperations([op], waitUntilFinished: true)
    }

}
