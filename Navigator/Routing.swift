
//  Routable.swift
//
//  Created by Gregor Casar on 17/11/2016.
//  Copyright © 2016 Gregor Casar. All rights reserved.
//

import Foundation
import UIKit


public typealias RouteBundle = [String:String];
public typealias ViewControllerInflater = (Intent)->UIViewController?;
public typealias RouteConditionChecker = (Intent)->Bool;

//  The Routable protocol is not ment to initialize the ViewController but rather
//  to create an abstract way to set controller's paramaters after it was inflated.
//
//  This is done so the ViewController can be created either by code or inflated
//  from XIB or a Storyboard. A good way to look at it is as an Intent consumer:
//  the concept of Intent is well established in Android development where an Activity
//  can rebind itself or "react" to an Intent at any point in its lifecycle.
//
//  gcasar on 17/11/2016
public protocol IntentConsumer{
    func on(intent:Intent);
}

public protocol FromStoryboard{
    static var _STORYBOARD_ID:String{get set};
    static var _STORYBOARD_NAME:String{get set};
}

public enum RouterError: Error{
    case badSchema(String)
    case schemaDoesNotMatch(String)
}


//  todo: create protocol:ViewController
//  that declares container controllers.
//  these controlers contain child viewcontrollers that can be routed to
//  example: UINavigationController, UIPagerController
protocol NavigatableControlerContainer{
    func navigate(intent:Intent, child:UIViewController.Type)->UIViewController?;
}

public class Navigator{
    open static let instance = Navigator();

    public var window:UIWindow! = nil;

    public var router:Router = Router.instance;


    public func open(path:String){
        if let vc = router.route(path){
            window.rootViewController = vc;
        }
    }

    public func open(with:[UIApplicationLaunchOptionsKey: Any]?){
        window = UIWindow(frame: UIScreen.main.bounds);
        window.makeKeyAndVisible();

        open(path:"/");
    }

    func open(_ url:URL, with:[UIApplicationOpenURLOptionsKey : Any]){

    }
}

public class Router{
    //singleton
    open static let instance = Router();

    fileprivate struct MapKey: Hashable{
        let schema:URLSchema;
        let conditions:[RouteConditionChecker];
        let index:Int;

        static var count:Int = 0;

        init(_ schema:URLSchema, _ conditions:[RouteConditionChecker]){
            MapKey.count = MapKey.count+1;
            self.schema = schema;
            self.index = MapKey.count;
            self.conditions = conditions;
        }

        var hashValue: Int {
            return schema._hashValue + index*31;//from effective java book
        }

        static func == (lhs: MapKey, rhs: MapKey) -> Bool {
            return lhs.schema.hashValue == rhs.schema.hashValue && lhs.index == rhs.index;
        }
    }

    private var controllerInflaters:[MapKey:ViewControllerInflater] = [:];

    //todo: sort by alphabet or rather use a better collection
    var schemasByLength:[Int:[URLSchema]] = [:];
    //organized by minimal length
    var wildcardSchemas:[Int:[URLSchema]] = [:];

    private var mapKeysBySchema:[URLSchema:[MapKey]] = [:];

    init(){
        //empty const
    }

    //populates a new router instance that serves as a simple paramater parser
    init(_ schemas:[String]) throws {
        for path in schemas{
            let schema = try URLSchema(fromPath: path)
            let key = MapKey(schema, []);
            add(schema, for: key);
            print("Adding ", schema._parsedStructure);
        }
    }

    @discardableResult
    public func map(
        path:String,
        to: @escaping ViewControllerInflater)->URLSchema
    {
        return map(path: path, where: [], to: to);
    }

    @discardableResult
    public func map(
        path:String,
        where conditions:[RouteConditionChecker],
        to: @escaping ViewControllerInflater)
        ->URLSchema
    {
        let schema = try! URLSchema(fromPath:path);
        let key = MapKey(schema, conditions);
        controllerInflaters[key] = to;
        add(schema, for: key);
        return schema;
    }

    ///
    /// Insert an array of routes
    ///
    @discardableResult
    public func map(
        _ maps:[[String:Any]]
        )->[URLSchema]
    {
        var results:[URLSchema] = [];
        for dict in maps{
            if  let path = dict["path"] as? String,
                let inflater = dict["to"] as? ViewControllerInflater{

                var conditions = (dict["where"] as? [RouteConditionChecker]) ?? [];
                if let condition = dict["where"] as? RouteConditionChecker{
                    conditions.append(condition);
                }

                results.append(map(path:path, where:conditions, to:inflater));
            }
        }
        return results;
    }

    private func add(_ schema:URLSchema, for key:MapKey){

        var mapKeys = mapKeysBySchema[schema] ?? [];
        mapKeys.append(key);
        mapKeysBySchema[schema] = mapKeys;

        if schema.endsInWildcard {
            var schemas = wildcardSchemas[schema.components.count] ?? [];
            schemas.append(schema)
            wildcardSchemas[schema.components.count] = schemas;
        }else{
            var schemas = schemasByLength[schema.components.count] ?? [];
            schemas.append(schema);
            schemasByLength[schema.components.count] = schemas;
        }
    }

    public func route(_ path:String) -> UIViewController?{
        if let intent = findMatchingSchema(forPath: path){
            return controller(from:intent);
        }

        return nil;
    }

    public func match(_ path:String) -> Intent?{
        return findMatchingSchema(forPath: path);
    }

    //  returns nil if schema could not be matched, else returns populated intent
    func findMatchingSchema(forPath path:String)->Intent?{
        let components = getComponents(inPath: path);

        if let intent = findMatchingSchema(components,path,schemasByLength[components.count]){
            return intent;
        }

        //and now for the wildcard schemas
        var count = components.count;
        repeat{
            if let schemas = wildcardSchemas[count]{
                if let intent = findMatchingSchema(components, path, schemas){
                    return intent;
                }
            }
            count = count-1;
        } while count > 0;

        return nil;
    }

    private func findMatchingSchema(_ components:[String], _ path:String, _ possibleSchemas:[URLSchema]? )->Intent?{
        if let possibleSchemas = possibleSchemas{
            for schema:URLSchema in possibleSchemas{
                if let bundle = schema.matches(pathComponents: components){
                    if let mapKeys = mapKeysBySchema[schema]{
                        for key in mapKeys{
                            let intent = Intent(path,components,bundle,schema,key,self);

                            var passedConditions = true;

                            for condition in key.conditions{
                                if !condition(intent) {
                                    passedConditions = false;
                                    break;
                                }
                            }

                            if passedConditions{
                                return intent;
                            }
                        }
                    }

                }
            }
        }
        return nil;
    }

    public func controller(from intent:Intent)->UIViewController?{
        if let inflater = controllerInflaters[intent.key]{
            return inflater(intent);
        }
        return nil;
    }


    private static func handle(_ vc:UIViewController, intent:Intent)->UIViewController{
        if let vcr:IntentConsumer = vc as? IntentConsumer{
            vcr.on(intent:intent);
        }

        return vc;
    }



    //wrapper function
    public static func controller(_ viewControllerType:UIViewController.Type)->ViewControllerInflater{
        if let vct = viewControllerType as? FromStoryboard.Type{
            return controllerFromStoryboard(vct);
        }else{
            let vct:UIViewController.Type = viewControllerType;
            return {
                return handle(vct.init(), intent:$0);
            }
        }
    }

    public static func controller(_ viewControllerName:String, inStoryboard:String)->ViewControllerInflater{
        let name = viewControllerName;
        let storyboard = inStoryboard;
        return {
            let storyboard = UIStoryboard(name: storyboard, bundle: nil)
            let vc = storyboard.instantiateViewController(withIdentifier: name)
            return handle(vc, intent:$0);
        }
    }

    public static func controllerFromStoryboard(_ viewControllerType:FromStoryboard.Type)->ViewControllerInflater{
        let name = viewControllerType._STORYBOARD_ID;
        let storyboard = viewControllerType._STORYBOARD_NAME;
        return {
            let storyboard = UIStoryboard(name: storyboard, bundle: nil)
            let vc = storyboard.instantiateViewController(withIdentifier: name)
            return handle(vc, intent:$0);
        }
    }

}

//TODO: extend by also using components of (URLComponents) other than path
//ex: full scheme is "https://gcasar.si:666/match/12/comments/?salt=eF3R"
//ex: at the moment only the "/match/12/comments/" is used in our routing
public struct URLSchema{
    //raw structure information
    //ex: /match/:id/comments/
    let path:String;
    //this is the underlying structure on which we base our comparison
    //ex: /match/:/comments/
    let _parsedStructure:String;

    //parsed structure information
    //in order
    let parameters:[URLSchemaParamater];//ex: [URLParamater("id",0)]
    //comprised of string literals and URLParameter objects
    let components:[Any];//ex: ["match",parameters[0]]

    let endsInWildcard:Bool;

    let _hashValue:Int;

    //valid definition is the Path component of an URL where each directory can
    //be either a string literal or a variable with a string literal named
    //ex: /match/:id/comments/, match/:apple/comments
    //ex: both paths above parse into an equal scheme definition that will equal
    //ex: if compared with == or by its hashValue, but will produce diferent
    //ex: dictionaries when parsing strings
    //throws RouterError#badSchema
    init(fromPath path:String) throws {
        self.path = path;

        var structure = "";//start with an empty structure
        var params:[URLSchemaParamater] = [];
        var components:[Any] = [];
        for (i, str) in getComponents(inPath:path).enumerated(){
            if str.hasPrefix(":") {
                let name = str.substring(from:str.index(after: str.startIndex))

                if name.characters.count == 0{
                    throw RouterError.badSchema("Parameter \(i) has no name");
                }

                structure+="/$";
                let parameter = URLSchemaParamater(named:name, index: i)
                params.append(parameter);
                components.append(parameter);

            }else if str.compare("*") == ComparisonResult.orderedSame{
                //wildcard
                if str.characters.count > 1{
                    throw RouterError.badSchema("Wildcard \(i) is malformed");
                }

                structure+="/*";
                components.append(URLSchemaWildcard(index: i));
            }else{
                //consider it a string literal
                structure+=("/"+str);
                components.append(str);
            }
        }

        self.parameters = params;
        self.endsInWildcard = (components.last as? URLSchemaWildcard) != nil;

        if (components.last as? String)?.compare("/")==ComparisonResult.orderedSame{
            components.removeLast();
            structure = structure.substring(to: structure.index(before: structure.endIndex));
        }

        self.components = components;

        _parsedStructure = structure;
        _hashValue = _parsedStructure.hashValue;
    }

    func matches(path:String)->RouteBundle?{
        return matches(pathComponents:getComponents(inPath: path));
    }

    func matches(pathComponents components:[String])->RouteBundle?{
        guard components.count == self.components.count || self.endsInWildcard else{
            return nil;
        }

        var siter = components.makeIterator();
        var citer = self.components.makeIterator();

        var paramDict:RouteBundle = [:];
        while let str = siter.next(), let comp = citer.next(){
            if let param:URLSchemaParamater = comp as? URLSchemaParamater{
                //todo: parse to specific type here
                paramDict[param.name] = str;
            }else if comp is URLSchemaWildcard{
                //continue
            }else{
                //component MUST be a string
                let compstr = comp as! String;

                guard compstr.compare(str) == ComparisonResult.orderedSame else{
                    return nil;
                }

            }
        }

        return paramDict;
    }

    //throws RouterError#schemaDoesNotMatch
    static func parseParameters(fromPath path:String, basedOn schema:URLSchema) throws -> RouteBundle{
        let components = getComponents(inPath:path);
        if components.count != schema.components.count{
            throw RouterError.schemaDoesNotMatch("Scheme lengths for \(path) and \(schema._parsedStructure) do not match");
        }

        var paramDict:RouteBundle = [:];
        for param in schema.parameters {
            let rawParameterValue = components[param.indexInSchema];
            paramDict[param.name] = rawParameterValue;
        }

        return paramDict;
    }

}


extension URLSchema: Hashable{

    public var hashValue: Int {
        return _hashValue;
    }

    public static func == (lhs: URLSchema, rhs: URLSchema) -> Bool {
        return lhs.hashValue == rhs.hashValue;
    }
}

//todo: additional metadata such as parameter type
struct URLSchemaParamater{
    let indexInSchema:Int;
    let name:String;

    init(named:String, index:Int){
        self.indexInSchema = index;
        self.name = named;
    }
}

struct URLSchemaWildcard{
    let indexInSchema:Int;

    init(index:Int){
        self.indexInSchema = index;
    }
}

struct RoutableMetadata{
    let controller:IntentConsumer;
    let timestamp:Date;
}

public struct Intent{
    var url:URL? = nil;
    let path:String;
    let components:[String];
    let bundle:RouteBundle;
    let schema:URLSchema;
    let router:Router;

    fileprivate let key:Router.MapKey;

    fileprivate init(_ path:String, _ components:[String], _ bundle:RouteBundle, _ schema:URLSchema, _ key:Router.MapKey, _ router:Router){
        self.path = path;
        self.components = components;
        self.bundle = bundle;
        self.schema = schema;
        self.key = key;
        self.router = router;
    }

}

//mark: util
fileprivate func getComponents(inPath path: String) -> [String] {
    let url:URL = URL(fileURLWithPath: path);
    var result:[String] = [];
    
    let pathComponents = url.pathComponents;
    
    for pathComponent in pathComponents {
        if pathComponent == "/" {
            continue
        }
        result.append(pathComponent)
    }
    
    
    if result.last?.compare("*") == ComparisonResult.orderedSame &&
        path.hasSuffix("/"){
        //append this to diferentiate between an open ended wildcard 
        //and an wildcard in a path component
        result.append("/");
    }
    
    if result.count == 0{
        result.append("");
    }
    
    return result
}
