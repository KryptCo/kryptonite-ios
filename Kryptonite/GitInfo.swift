//
//  GitInfo.swift
//  Kryptonite
//
//  Created by Kevin King on 5/22/17.
//  Copyright © 2017 KryptCo. All rights reserved.
//

import JSON

struct InvalidGitInfo:Error{}

enum GitInfo:Jsonable {
    case commit(CommitInfo)
    case tag(TagInfo)
    init(json: Object) throws {
        if json["commit"] as? String != nil && json["tag"] as? String != nil {
            throw InvalidGitInfo()
        }
        if let commit = json["commit"] as? Object {
            self = .commit(try CommitInfo(json: commit))
            return
        }
        if let tag = json["tag"] as? Object {
            self = .tag(try TagInfo(json: tag))
            return
        }
        throw InvalidGitInfo()
    }

    var object: Object {
        switch self {
        case .commit(let c):
            return ["commit": c.object]
        case .tag(let t):
            return ["tag": t._object]
        }
    }
    
    var subtitle: String {
        switch self {
        case .commit(_):
            return "Git Commit"
        case .tag(_):
            return "Git Tag"
        }
    }

    var shortDisplay: String {
        switch self {
        case .commit(let c):
            return c.shortDisplay
        case .tag(let t):
            return t.shortDisplay
        }
    }
}
