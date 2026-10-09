import XCTest
import Observation
@testable import TaskFlow

@MainActor
final class CollaborationPlanStateTests: XCTestCase {
 private func fixture() -> CollaborationPlanState {
  PlanStateURLProtocol.delayFirst = false
  PlanStateURLProtocol.planCalls = 0
  PlanStateURLProtocol.failure = false
  PlanStateURLProtocol.status = "draft"
  let config = URLSessionConfiguration.ephemeral
  config.protocolClasses = [PlanStateURLProtocol.self]
  return CollaborationPlanState(api: APIClient(session: URLSession(configuration: config)))
 }
 func testRecreatedGraphUsesLoadedSnapshotWithoutNewRequests() async {
  let state=fixture()
  await state.load(taskID:"card",reloadToken:0,isOwner:true)
  XCTAssertEqual(state.draftPlan?.id,"plan");XCTAssertTrue(state.isVisible)
  await state.load(taskID:"card",reloadToken:0,isOwner:true)
  XCTAssertEqual(PlanStateURLProtocol.planCalls,1)
 }
 func testForcedReloadPublishesApprovalAndFailureKeepsVisibleData() async {
  let state=fixture()
  await state.load(taskID:"card",reloadToken:0,isOwner:true)
  PlanStateURLProtocol.failure=true
  await state.load(taskID:"card",reloadToken:0,force:true,isOwner:true)
  XCTAssertEqual(state.draftPlan?.id,"plan");XCTAssertTrue(state.isVisible)
  PlanStateURLProtocol.failure=false;PlanStateURLProtocol.status="approved"
  await state.load(taskID:"card",reloadToken:1,isOwner:true)
  XCTAssertNil(state.draftPlan);XCTAssertEqual(state.plan?.status,"approved")
 }
 func testConcurrentProbesFetchOnlyOnce() async {
  let state=fixture()
  async let first: Void=state.load(taskID:"card",reloadToken:0,isOwner:true)
  async let second: Void=state.load(taskID:"card",reloadToken:0,isOwner:true)
  _ = await (first,second)
  XCTAssertEqual(PlanStateURLProtocol.planCalls,1)
 }
 func testEventDuringSnapshotLoadIsNotLost() async {
  let state=fixture()
  PlanStateURLProtocol.delayFirst=true
  let first=Task { await state.load(taskID:"card",reloadToken:0,isOwner:true) }
  while PlanStateURLProtocol.planCalls==0 { await Task.yield() }
  PlanStateURLProtocol.status="approved"
  await state.load(taskID:"card",reloadToken:1,force:true,isOwner:true)
  await first.value
  XCTAssertEqual(state.plan?.status,"approved")
  XCTAssertNil(state.draftPlan)
 }
 func testUnchangedPollingDoesNotInvalidateVisibleSnapshot() async {
  let state=fixture()
  await state.load(taskID:"card",reloadToken:0,isOwner:true)
  let changed=ChangeFlag()
  withObservationTracking { _ = state.draftPlan; _ = state.isVisible } onChange: { changed.value=true }
  await state.load(taskID:"card",reloadToken:0,force:true,isOwner:true)
  XCTAssertFalse(changed.value)
 }
}
private final class ChangeFlag: @unchecked Sendable { var value=false }
private final class PlanStateURLProtocol: URLProtocol {
 static var delayFirst=false
 static var planCalls=0
 static var failure=false
 static var status="draft"
 override class func canInit(with request: URLRequest)->Bool { true }
 override class func canonicalRequest(for request: URLRequest)->URLRequest {request}
 override func startLoading() {
  let path=request.url!.path
  var code=200
  var body="[]"
  if path.hasSuffix("collaboration-plans") {
   Self.planCalls+=1
   if Self.failure {code=500;body="{\"error\":\"test failure\"}"}
   else {body="{\"plans\":[{\"id\":\"plan\",\"task_id\":\"card\",\"revision\":1,\"status\":\"\(Self.status)\",\"profile\":\"manual\",\"rationale\":\"work\",\"nodes\":[],\"edges\":[]}]}"}
  } else if path.hasSuffix("roles") {body="{\"roles\":[]}"}
  let deliver = {
  self.client?.urlProtocol(self,didReceive:HTTPURLResponse(url:self.request.url!,statusCode:code,httpVersion:nil,headerFields:["Content-Type":"application/json"])!,cacheStoragePolicy:.notAllowed)
  self.client?.urlProtocol(self,didLoad:Data(body.utf8));self.client?.urlProtocolDidFinishLoading(self)
  }
  if Self.delayFirst && path.hasSuffix("collaboration-plans") && Self.planCalls==1 {
   DispatchQueue.global().asyncAfter(deadline:.now()+0.08,execute:deliver)
  } else { deliver() }
 }
 override func stopLoading() {}
}
