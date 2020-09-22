xquery version "3.1";

(:~
 : A set of helper functions to access the application context from
 : within a module.
 :)
module namespace config="http://xquery.weber-gesamtausgabe.de/modules/config";

declare namespace repo="http://exist-db.org/xquery/repo";
declare namespace expath="http://expath.org/ns/pkg";
declare namespace tei="http://www.tei-c.org/ns/1.0";
declare namespace mei="http://www.music-encoding.org/ns/mei";
declare namespace output="http://www.w3.org/2010/xslt-xquery-serialization";
declare namespace xmldb="http://exist-db.org/xquery/xmldb";
declare namespace map="http://www.w3.org/2005/xpath-functions/map";
declare namespace request="http://exist-db.org/xquery/request";
declare namespace session="http://exist-db.org/xquery/session";

import module namespace json="http://www.json.org";
import module namespace templates="http://exist-db.org/xquery/templates";
import module namespace functx="http://www.functx.com";
import module namespace core="http://xquery.weber-gesamtausgabe.de/modules/core" at "core.xqm";
import module namespace lang="http://xquery.weber-gesamtausgabe.de/modules/lang" at "lang.xqm";
import module namespace query="http://xquery.weber-gesamtausgabe.de/modules/query" at "query.xqm";
import module namespace norm="http://xquery.weber-gesamtausgabe.de/modules/norm" at "norm.xqm";
import module namespace wdt="http://xquery.weber-gesamtausgabe.de/modules/wdt" at "wdt.xqm";
import module namespace str="http://xquery.weber-gesamtausgabe.de/modules/str" at "xmldb:exist:///db/apps/WeGA-WebApp-lib/xquery/str.xqm";

(: 
    Determine the application root collection from the current module load path.
:)
declare variable $config:app-root as xs:string := 
    let $rawPath := replace(system:get-module-load-path(), '/null/', '//')
    let $modulePath :=
        (: strip the xmldb: part :)
        if (starts-with($rawPath, "xmldb:exist://")) then
            if (starts-with($rawPath, "xmldb:exist://embedded-eXist-server")) then
                substring($rawPath, 36)
            else
                substring($rawPath, 15)
        else
            $rawPath
    return
        substring-before($modulePath, "/modules")
;

declare variable $config:catalogues-collection-path as xs:string := $config:app-root || '/catalogues';
declare variable $config:options-file-path as xs:string := $config:catalogues-collection-path || '/options.xml';
declare variable $config:options-file as document-node() := doc($config:options-file-path);
declare variable $config:data-collection-path as xs:string := config:get-option('dataCollectionPath');
declare variable $config:svn-change-history-file as document-node()? := 
    if(doc-available($config:data-collection-path || '/subversionHistory.xml')) then doc($config:data-collection-path || '/subversionHistory.xml')
    else ();
declare variable $config:tmp-collection-path as xs:string := $config:app-root || '/tmp';
declare variable $config:xsl-collection-path as xs:string := $config:app-root || '/xsl';
declare variable $config:smufl-decl-file-path as xs:string := $config:catalogues-collection-path || '/charDecl.xml';
declare variable $config:swagger-config-path as xs:string := $config:app-root || '/api/v1/swagger.json';

declare variable $config:isDevelopment as xs:boolean := $config:options-file/id('environment') eq 'development';

declare variable $config:repo-descriptor as element(repo:meta) := doc(concat($config:app-root, "/repo.xml"))/repo:meta;

declare variable $config:valid-resource-suffixes as xs:string* := ('html', 'htm', 'json', 'xml', 'tei', 'txt');

(: collection that provides XSL scripts for transforming our documents to external schemas, e.g. tei_all :)
declare variable $config:xsl-external-schemas-collection-path as xs:string := $config:app-root || '/resources/lib/WeGA-ODD/xsl';

(: The first language is the default language :)
declare variable $config:valid-languages as xs:string* := ('de', 'en');

declare variable $config:default-date-picture-string := function($lang as xs:string) as xs:string? {
    if($lang = 'de') then '[D1o] [MNn] [Y]' 
    else if ($lang = 'en') then '[MNn] [D], [Y]'
    else ()
};

(:~
 : get and set language variable
 : if $lang is an empty-sequence or an empty string, the function first looks at the URL, 
 : second at the current session before falling back to the first entry in $config:valid-languages
 :
 : @author Peter Stadler
 : @param $lang the language to set
 : @return xs:string the (newly) set language variable 
 :)
declare function config:guess-language($lang as xs:string?) as xs:string {
    let $urlPathSegment := if(request:exists()) then tokenize(request:get-attribute('$exist:path'), '/')[2] else ()
    let $sessionParam := if(session:exists()) then session:get-attribute('lang') else ()
    let $default-option := $config:valid-languages[1]
    return
        if($lang = $config:valid-languages) then ($lang, session:set-attribute('lang', $lang))
        else if($urlPathSegment = $config:valid-languages) then ($urlPathSegment, session:set-attribute('lang', $urlPathSegment))
        else if($sessionParam = $config:valid-languages) then $sessionParam
        else $default-option
};

(:~
 : Resolve the given path using the current application context.
 : If the app resides in the file system,
 :)
declare function config:resolve($relPath as xs:string) {
    if (starts-with($config:app-root, "/db")) then
        doc(concat($config:app-root, "/", $relPath))
    else
        doc(concat("file://", $config:app-root, "/", $relPath))
};

(:~
 : Returns the repo.xml descriptor for the current application.
 :)
declare function config:repo-descriptor() as element(repo:meta) {
    $config:repo-descriptor
};

(:~
 : Returns the expath-pkg.xml descriptor for the current application.
 :)
declare function config:expath-descriptor() as element(expath:package) {
    doc(concat($config:app-root, "/expath-pkg.xml"))/expath:package
};

(:~
 :  Returns the requested option value from an option file given by the variable $wega:optionsFile
 :  
 : @author Peter Stadler
 : @param $key the key to look for in the options file
 : @return xs:string the option value as string identified by the key otherwise the empty sequence
 :)
declare function config:get-option($key as xs:string?) as xs:string? {
    let $result := str:normalize-space($config:options-file/id($key))
    return
        if($result) then $result
        else core:logToFile('warn', 'config:get-option(): unable to retrieve the key "' || $key || '"')
};

(:~
 :  Set or add a preference for the WeGA WebApp
 :  This can be used by a trigger to inject options on startup or to change options dynamically during runtime
 :  NB: You have to be logged in as admin to be able to update preferences!
 : 
 :  @param $key the key to update or insert 
 :  @param $value the value for $key
 :  @return the new value if successful, the empty sequence otherwise
~:)
declare function config:set-option($key as xs:string, $value as xs:string) as xs:string? {
    let $old := $config:options-file/id($key)
    return
        if($old) then try {(
            update value $old with $value,
            core:logToFile('debug', 'set preference "' || $key || '" to "' || $value || '"'),
            $value
            )}
            catch * { core:logToFile('error', 'failed to set preference "' || $key || '" to "' || $value || '". Error was ' || string-join(($err:code, $err:description), ' ;; ')) }
        else try {( 
            update insert <entry xml:id="{$key}">{$value}</entry> into $config:options-file/id('various'),
            core:logToFile('debug', 'added preference "' || $key || '" with value "' || $value || '"'),
            $value
            )}
            catch * { core:logToFile('error', 'failed to add preference "' || $key || '" with value "' || $value || '". Error was ' || string-join(($err:code, $err:description), ' ;; ')) }
};

(:~
 : Gets document type by ID
 : Serves as a general validation service for our ID taxonomy
 :
 : @author Peter Stadler
 : @param $id 
 : @return xs:string document type
:)
declare function config:get-doctype-by-id($id as xs:string?) as xs:string? {
    for $func in $wdt:functions
    return 
        if($func($id)('check')() and $func($id)('prefix')) then $func($id)('name')
        else ()
};

declare function config:get-combined-doctype-by-id($id as xs:string?) as xs:string* {
    for $func in $wdt:functions
    return 
        if($func($id)('check')()) then $func($id)('name')
        else ()
};

(:~
 : Checks whether a given id matches the WeGA pattern of person ids
 :
 : @author Peter Stadler
 : @param $docID the id to test as string
 : @return xs:boolean
:)
declare function config:is-person($docID as xs:string?) as xs:boolean {
    matches($docID, '^A00[0-9A-F]{4}$')
};

(:~
 : Checks whether a given id matches the WeGA pattern of iconography ids
 :
 : @author Peter Stadler
 : @param $docID the id to test as string
 : @return xs:boolean
:)
declare function config:is-iconography($docID as xs:string?) as xs:boolean {
    matches($docID, '^A01\d{4}$')
};

(:~
 : Checks whether a given id matches the WeGA pattern of work ids
 :
 : @author Peter Stadler
 : @param $docID the id to test as string
 : @return xs:boolean
:)
declare function config:is-work($docID as xs:string?) as xs:boolean {
    matches($docID, '^A02\d{4}$')
};

(:~
 : Checks whether a given id matches the WeGA pattern of writing ids
 :
 : @author Peter Stadler
 : @param $docID the id to test as string
 : @return xs:boolean
:)
declare function config:is-writing($docID as xs:string?) as xs:boolean {
    matches($docID, '^A03\d{4}$')
};

(:~
 : Checks whether a given id matches the WeGA pattern of letter ids
 :
 : @author Peter Stadler
 : @param $docID the id to test as string
 : @return xs:boolean
:)
declare function config:is-letter($docID as xs:string?) as xs:boolean {
    matches($docID, '^A04\d{4}$')
};

(:~
 : Checks whether a given id matches the WeGA pattern of news ids
 :
 : @author Peter Stadler
 : @param $docID the id to test as string
 : @return xs:boolean
:)
declare function config:is-news($docID as xs:string?) as xs:boolean {
    matches($docID, '^A05\d{4}$')
};

(:~
 : Checks whether a given id matches the WeGA pattern of diary ids
 :
 : @author Peter Stadler
 : @param $docID the id to test as string
 : @return xs:boolean
:)
declare function config:is-diary($docID as xs:string?) as xs:boolean {
    matches($docID, '^A06\d{4}$')
};

(:~
 : Checks whether a given id matches the WeGA pattern of var ids
 :
 : @author Peter Stadler
 : @param $docID the id to test as string
 : @return xs:boolean
:)
declare function config:is-var($docID as xs:string?) as xs:boolean {
    matches($docID, '^A07\d{4}$')
};

(:~
 : Checks whether a given id matches the WeGA pattern of biblio ids
 :
 : @author Peter Stadler
 : @param $docID the id to test as string
 : @return xs:boolean
:)
declare function config:is-biblio($docID as xs:string?) as xs:boolean {
    matches($docID, '^A11\d{4}$')
};

(:~
 : Checks whether a given id matches the WeGA pattern of places ids
 :
 : @author Peter Stadler
 : @param $docID the id to test as string
 : @return xs:boolean
:)
declare function config:is-place($docID as xs:string?) as xs:boolean {
    matches($docID, '^A13\d{4}$')
};

(:~
 : Checks whether a given id matches the WeGA pattern of sources ids
 :
 : @author Peter Stadler
 : @param $docID the id to test as string
 : @return xs:boolean
:)
declare function config:is-source($docID as xs:string?) as xs:boolean {
    matches($docID, '^A22\d{4}$')
};

(:~
 : Checks whether a given id matches the WeGA pattern of org ids
 :
 : @author Peter Stadler
 : @param $docID the id to test as string
 : @return xs:boolean
:)
declare function config:is-org($docID as xs:string?) as xs:boolean {
    matches($docID, '^A08[0-9A-F]{4}$')
};

(:~
 : Checks whether a given id matches the WeGA pattern of addenda ids
 :
 : @author Peter Stadler
 : @param $docID the id to test as string
 : @return xs:boolean
:)
declare function config:is-addenda($docID as xs:string?) as xs:boolean {
    matches($docID, '^A12[0-9]{4}$')
};

(:~
 : Checks whether a given document is from the series "Weber-Studien" published by the WeGA
 :
 : @author Peter Stadler
 : @param $docID the id to test as string
 : @return xs:boolean
:)
declare function config:is-weberStudies($doc as document-node()?) as xs:boolean {
    $doc//tei:series/tei:title[@level = 's'] = 'Weber-Studien'
};

(:~
 : Checks whether a given string matches the defined types of bibliographic objects
 :
 : @author Peter Stadler
 : @param $string the string to test
 : @return xs:boolean
:)
declare function config:is-biblioType($string as xs:string?) as xs:boolean {
    $string = ('mastersthesis', 'inbook', 'online', 'review', 'book', 'misc', 'inproceedings', 'article', 'score', 'incollection', 'phdthesis')
};

(:~
 : Checks the id for well-formedness and returns its collection path. Doesn't check for availability!
 :
 : @author Peter Stadler
 : @param $docID the id of the TEI document
 : @return xs:string the collection path of the document 
:)
declare function config:getCollectionPath($docID as xs:string) as xs:string? {
    let $docType := config:get-doctype-by-id($docID)
    return 
        if(exists($docType)) then str:join-path-elements(($config:data-collection-path, $docType, replace($docID, '[0-9A-F]{2}$', 'xx'))) 
        else ()
};

(:~
 : Returns whether WeGA-data was updated after a given dateTime. 
 : If $dateTime is not castable as xs:dateTime or $config:svn-change-history-file is not present it returns true().
 :
 : @author Peter Stadler
 : @param $dateTime the date to check
 : @return xs:boolean
:)
declare function config:eXistDbWasUpdatedAfterwards($dateTime as xs:dateTime?) as xs:boolean {
    if($dateTime castable as xs:dateTime) then config:getDateTimeOfLastDBUpdate() > ($dateTime cast as xs:dateTime)
    else true()
};

(:~
 : Retrieves the dateTime of last eXist-db update by checking svnChangeHistoryFile
 :
 : @author Peter Stadler
 : @return xs:dateTime
:)
declare function config:getDateTimeOfLastDBUpdate() as xs:dateTime? {
    if($config:svn-change-history-file) then xmldb:last-modified($config:data-collection-path, 'subversionHistory.xml')
    else ()
};

(:~
 : Returns the current head revision of the database as given by the 'svnChangeHistoryFile'
 :
 : @author Peter Stadler
 : @return xs:int
:)
declare function config:getCurrentSvnRev() as xs:int? {
    if($config:svn-change-history-file/dictionary/@head castable as xs:int) then $config:svn-change-history-file/dictionary/@head cast as xs:int
    else ()
};

(:~
 : Retrieves some subversion properties (latest revision, author, dateTime) for a given document ID
 :
 : @author Peter Stadler
 : @param $docID the document ID
 : @return map()
:)

declare function config:get-svn-props($docID as xs:string) as map(*) {
    map:merge(
        for $prop in $config:svn-change-history-file//id($docID)/@*
        return map:entry(local-name($prop), data($prop))
    )
};


(:~
 : Create parameters for xsl transformations 
 :
 : @author Peter Stadler
 : @return parameters
:)
declare function config:get-xsl-params($params as map(*)?) as element(parameters) {
    <parameters>
        <param name="lang" value="{config:guess-language(())}"/>
        <param name="optionsFile" value="{$config:options-file-path}"/>
        <param name="baseHref" value="{core:link-to-current-app(())}"/>
        <param name="smufl-decl" value="{$config:smufl-decl-file-path}"/>
        <param name="catalogues-collection-path" value="{$config:catalogues-collection-path}"/>
        <param name="data-collection-path" value="{$config:data-collection-path}"/>
        <param name="environment" value="{config:get-option('environment')}"/>
        {if(exists($params)) then 
            for $i in map:keys($params)
            return 
                <param name="{$i}" value="{map:get($params, $i)}"/>
        else ()
        }
    </parameters>
};

(:~
 : get (from URL parameter, or session, or options file) and set (to the session) the default entries per page
~:)
declare function config:entries-per-page() as xs:int {
    let $urlParam := if(request:exists()) then request:get-parameter('limit', ()) else ()
    let $sessionParam := if(session:exists()) then session:get-attribute('limit') else ()
    let $default-option := config:get-option('entriesPerPage')
    return
        if($urlParam castable as xs:int and xs:int($urlParam) <= 50) then (xs:int($urlParam), session:set-attribute('limit', xs:int($urlParam)))
        else if($sessionParam castable as xs:int) then $sessionParam
        else if($default-option castable as xs:int) then xs:int($default-option)
        else (10, core:logToFile('error', 'Failed to get default "entriesPerPage" from options file. Falling back to "10"!'))
};

(:~
 : get (from URL parameter, or session, or options file) and set (to the session) the line wrap preference of the user
~:)
declare function config:line-wrap() as xs:boolean {
    let $urlParam := if(request:exists()) then request:get-parameter('line-wrap', ()) else ()
    let $sessionParam := if(session:exists()) then session:get-attribute('line-wrap') else ()
    let $default-option := true() (:config:get-option('line-wrap'):)
    return
        if($urlParam) then 
            if($urlParam = ('true', '1', 'yes')) then (true(), session:set-attribute('line-wrap', true()))
            else (false(), session:set-attribute('line-wrap', false()))
        else if($sessionParam instance of xs:boolean) then $sessionParam
        else if($default-option instance of xs:boolean) then $default-option
        else (true(), core:logToFile('error', 'Failed to get default "line-wrap" from options file. Falling back to "true"!'))
};

(:~
 : Return the Swagger API base path
~:)
declare function config:api-base() as xs:string {
    let $swagger-config := json-doc($config:swagger-config-path)
    return
        $swagger-config?schemes[1] || '://' || $swagger-config?host || $swagger-config?basePath 
};

(:~
 : set/update object in swagger.json description.
 : NB: You have to be logged in as admin to be able to update preferences!
 :
 : @param $key a sequence of keys navigating to the object; 
 :  e.g. the sequence ('foo', 'bar') will select the object 'bar' within the object 'foo'. 
 :  Non existing keys will be added, existing keys will be updated
 : @param $value the value of the new or updated key. 
 :  String values will be parsed as JSON, so you can pass objects or arrays via
 :  environment variables. NB: JSON strings need to be wrapped in double quotes!  
 : @return the new value if successful, the empty sequence otherwise
 :)
declare function config:set-swagger-option($key as xs:string*, $value as item()?) as item()? {
    let $swagger.json := fn:json-doc($config:swagger-config-path)
    let $valueJSON := 
        typeswitch($value)
        case xs:string return
            try { parse-json($value) }
            catch * { $value } (: parse-json() fails for simple string values  :)
        case node() return parse-json(json:xml-to-json($value)) (: the output of json:xml-to-json() seems to be a string, not a map object :)
        case array(*) return $value
        case map(*) return $value
        default return core:logToFile('warn', 'config:set-swagger-option(): failed to convert value of ' || string-join($key, '.') || ' to a JSON object.')
    let $update := config:map-put-recursive($swagger.json, $key, $valueJSON)
    let $serialize-json := function($json as item()) as xs:string {
        serialize($json, <output:serialization-parameters><output:method>json</output:method></output:serialization-parameters>)
    }
    let $update2string := $serialize-json($update)
    let $fileName := functx:substring-after-last($config:swagger-config-path, '/')
    let $collection := functx:substring-before-last($config:swagger-config-path, '/')
    let $update := 
        try { 
            xmldb:store($collection, $fileName, $update2string, 'application/json'),
            core:logToFile('debug', 'set swagger option "' || string-join($key, '.') || '" to "' || $serialize-json($valueJSON) || '"')
        }
        catch * { core:logToFile('error', 'config:set-swagger-option(): failed to set swagger option "' || string-join($key, '.') || '" to "' || $serialize-json($valueJSON) || '" -- Error was ' || string-join(($err:code, $err:description), ' ;; ')) }
    return
        if($update) then $valueJSON
        else ()
};

(:~
 : Recursively walk through a map object and update map objects therein.
 : Helper function for config:set-swagger-option()
 :)
declare %private function config:map-put-recursive($map as map(*), $key as xs:string+, $value as item()*) as map(*) {
    if(count($key) eq 1) 
    then map:put($map, $key, $value)
    else if(map:contains($map, $key[1]) and $map($key[1]) instance of map(*))
    then
        map:put(
            $map,
            $key[1],
            config:map-put-recursive($map($key[1]), subsequence($key, 2), $value)
        )
    else 
        map:put(
            $map,
            $key[1],
            config:map-put-recursive(map {}, subsequence($key, 2), $value)
        )
};
