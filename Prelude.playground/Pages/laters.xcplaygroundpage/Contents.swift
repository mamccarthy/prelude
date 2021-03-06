//
// This source file is part of Prelude, an open source project by Wayfair
//
// Copyright (c) 2018 Wayfair, LLC.
// Licensed under the 2-Clause BSD License
//
// See LICENSE.md for license information
//

import Foundation
import Prelude

//
// Laters
//

// a `Later` models an async function, here’s a simple one
let sendTrue = Laters.After(deadline: .now() + 1, queue: .main, value: true)

// a `Later` is a “suspended” (frozen), lazy computation. Nothing happens unless we call `run(_:)`:
sendTrue.run { boolValue in
    print("1. waited one second then received: \(boolValue)")
}

// a `Later` supports many of the other functional operators you are perhaps used to from other data types.
// you can think of `map(_:)` as either transforming the value that is “inside” a `Later`, or alternatively as “extending” the computation represented by a `Later` with an additional, synchronous “segment”:
sendTrue
    .map(!)
    .map { "here is the value we got: \($0)" }
    .map { $0.uppercased() }
    // nothing actually happens though until we call:
    .run { print("2. transformed: \($0)") }

// to extend a `Later` with an additional *asynchronous* segment, use `flatMap(_:)`.
// these two segments happen “in series”, so the following code will call its callback after 2 seconds have elapsed:
sendTrue
    .map(!)
    .flatMap { boolValue in Laters.After(deadline: .now() + 1, queue: .main, value: true && boolValue) }
    .map { "here’s what we got: \($0)" }
    .run { print("3. flatMap: \($0)") }

// as you might expect, by the end of this we’re gonna be talking about some networking stuff. Before we get there though, let’s discuss error-handling.
// `Later`s are designed to elegantly accommodate failable or error-producing functions. To signal an error yourself, you can use `map(_:)`’s close relative, `tryMap(_:)`:
sendTrue
    .tryMap { _ in throw NSError(domain: "", code: -1, userInfo: nil) }
    .run { print("4. here’s an error: \($0)") }

// as you can see, a `throw` inside a `tryMap(_:)` is converted to a Swift `Result` when it pops out in the callback.
// handling a `Later` that wraps a `Result` by hand can be verbose, so much of the remaining API is devoted to making this situation (where errors may be happening “upstream” of you) more friendly. One thing you can do is `replaceError(_:)`:
sendTrue
    .map { boolValue in "here’s a bool: \(boolValue)" }
    .tryMap { _ -> String in throw NSError(domain: "", code: -1, userInfo: nil) }
    .replaceError("there was an error :(")
    .run { print("5. here’s what happened: \($0)") }

// a more general concept is to `fold(transformValue:transformError:)`. This is like saying that no matter what value or error you get, you promise to convert either of them to some third “downstream” type:
sendTrue
    .tryMap { _ -> Bool in throw NSError(domain: "wendy’s drive thru", code: -1, userInfo: nil) }
    .fold(transformValue: { "\($0)" }, transformError: { $0.localizedDescription })
    .run { print("6. folded: \($0)") }

// we can also make the opposite situation more convenient. `mapSuccess(_:)` allows you to apply a transformation to just the `.success` case of whatever `Result` may be produced upstream of you:
sendTrue
    .tryMap { $0 }
    .mapSuccess { "ok: \($0)" }
    .run { print("7. mapped success: \($0)") }

// note also that a `Later` at any stage of transformation can always be saved out to another variable and re-used, or transformed further. Since `Later`s are always lazy, this is always safe to do, and nothing actually happens until `run(_:)` is called.
// just as with Combine and some other libraries, it’s best to `eraseToAnyLater()` if you plan on passing around a `Later` value a lot, otherwise the type can be unwieldy:
let sendFalseAsString: AnyLater<String> = sendTrue
    .map(!)
    .map { "\($0)" }
    .eraseToAnyLater()
// note though, that unlike promises et al, `Later`s have *no* caching or “sharing” feature, so calling `run(_:)` twice *always* executes the work twice:
sendFalseAsString.run { print("8. \($0)") }
sendFalseAsString.run { print("9. \($0)") }

// okay let’s do some networking!
let myURL = URL(string: "https://httpbin.org/get")!

// here’s a simple wrapper that calls through to the `URLSession` of your choice!
Laters.DataTask(request: URLRequest(url: myURL), session: .shared)
    // make sure we call the callback on the main thread…
    .dispatchAsync(on: .main)
    // it’s rude to run network code in a playground without asking, uncomment the following line to try it out…
//    .run { result in print("networking! \(result)") }

import PlaygroundSupport
PlaygroundPage.current.needsIndefiniteExecution = true

//
// `Later`s in Practice
//

// it’s fine to have all this stuff, but what about all the existing async code you already have? Consider the following function:
func myAsyncFunc(completion: @escaping () -> Void) {
    print("doin’ thangs")
    DispatchQueue.main.async {
        completion()
    }
}

// there are initializers for `AnyLater` that should be sufficient to “capture” any plain, callback-taking function and convert it to a `Later` in one step:
let a = AnyLater(myAsyncFunc)
a.run {
    print("ok")
}

func myAsyncFunc1(completion: @escaping (Bool) -> Void) {
    print("doin’ thangs")
    DispatchQueue.main.async {
        completion(true)
    }
}

let b = AnyLater(myAsyncFunc1) // => AnyLater<Bool>

func myAsyncFunc2(completion: @escaping (Bool, String) -> Void) {
    print("doin’ thangs")
    DispatchQueue.main.async {
        completion(true, "ok")
    }
}

// when a callback function returns more than one value, converting it to a `Later` gives you back a tuple
let c = AnyLater(myAsyncFunc2) // => AnyLater<(Bool, String)>

// final example. Let’s say you have a type that exposes a callback-based API:
struct MyService {
    func performWork(completion: @escaping (Bool) -> Void) {
        print("my service!")
        DispatchQueue.main.async {
            completion(true)
        }
    }
}

// one approach to `Later`-ize such an API is to extend the type and expose an `AnyLater` that directly references the method:
extension MyService {
    func performWorkLater() -> AnyLater<Bool> {
        AnyLater(self.performWork(completion:))
    }
}

// calling the API is then just
MyService().performWorkLater()
    .map { "10. do something with the thing: \($0)" }
    .run { _ in /* TODO */ }

//
// mess around with overloads of `AnyLater` to make sure they all compile zone
//

AnyLater<Void> { callback in callback() }
AnyLater<Void> { callback in callback(()) }
AnyLater<Void> { (callback: () -> Void) in }
AnyLater<Void> { (callback: (Void) -> Void) in }

AnyLater<Bool> { _ in }
AnyLater<(String, Int)> { _ in }
AnyLater<(Float, Void, [Double])> { $0((1.0, (), [])) }

//
// create a bunch of interdependent `NSOperation`s zone
//

var first = false
var second = false

// since a `Later` is an asynchronous blob of code that does nothing until we run it, we can write an operator (`.asOperation()`) to bridge between the world of Laters and the world of Foundation `NSOperations`…
let firstOperation = sendTrue
    .tap { first = $0 }
    .map { _ in () }
    .asOperation()

let secondOperation = Laters.After(deadline: .now() + 2, queue: .main, value: true)
    .tap { second = $0 }
    .map { _ in () }
    .asOperation()

let lastOperation = Laters.After(deadline: .now(), queue: .main, value: ())
    .tap { _ in print("first: \(first)") }
    .tap { _ in print("second: \(second)") }
    .asOperation()

// once you’ve converted a `Later` into an `Operation`, you can use the more elaborate features of `Operation`s on top of the work you already expressed inside the original Laters. Here’re some dependencies…
lastOperation.addDependency(firstOperation)
lastOperation.addDependency(secondOperation)

// these Laters, which we were able to define really quickly in a DSL-like style, now gain all the fancy features of `NSOperation`s for free. For example, these three operations will now fire in the order we specified (`assertOperation` is last):
let queue = OperationQueue()
queue.addOperations([lastOperation, firstOperation, secondOperation], waitUntilFinished: false)

//
// magical `MainQueue` zone
//

// finally, we can use some sneaky type tricks to add other useful information to certain Laters. A `MainQueueAnyLater` is a `Later` that is guaranteed to call its callback on the main thread:
let x: MainQueueAnyLater<Int> = sendTrue
    .map { $0 ? 9 : 999 }
    // the magic is in these two operators here. Any `Later` chain which ends with `.dispatchMain` followed by `.eraseToAnyLater` is “erased” to a `MainQueueAnyLater` (as opposed to just an `AnyLater`). This means that we can write UI functions — for example — which insists that its data be provided by `MainQueueAnyLater`s, which means we are guaranteed that we will be on the right thread before hitting the UI
    .dispatchMain()
    .eraseToAnyLater()

// ie. for a `MainQueueAnyLater`, this should always hold…
x.run { _ in precondition(Thread.isMainThread) }

// we can get the same level of safety for other queues as well. Imagine this is some special work queue we have:
let anotherQueue = DispatchQueue.global()

// we wrap it in a struct to “tag” it…
struct MyQueue: TaggedQueue {
    func getQueue() -> DispatchQueue {
        anotherQueue
    }
}

// and then do whatever we like with Laters API. The resulting type of any `Later` operations which end with a dispatch to that tagged queue, followed by `erase…`, yields a `TaggedQueueAnyLater` which the compiler knows is associated with `MyQueue`.
let y: TaggedQueueAnyLater<Bool, MyQueue> = sendTrue
    .dispatchAsync(taggedQueue: MyQueue())
    .eraseToAnyLater()

// you can then use this type signature to enforce, in the type system, that work is executing on the queues you require:
y
    .tap { _ in print("I’m on a global queue!") }
    .run { _ in precondition(!Thread.isMainThread) }

//
//
//

// bonus: the rare double-erase will turn a `MainQueueAnyLater` back into a regular `AnyLater`!
let z = Laters.After(deadline: .now(), queue: .global(), value: ())
    .dispatchMain()
    .eraseToAnyLater()
    .eraseToAnyLater()
