// ref: sdef(5) man page
// ref: file:///System/Library/DTDs/sdef.dtd

import { create } from 'xmlbuilder2';

import type { XMLBuilder, XMLWriterOptions } from 'xmlbuilder2/lib/interfaces.js';

type NonEmptyArray<T> = [T, ...T[]];

type RequireAtLeastOne<T, Keys extends keyof T = keyof T> = Omit<T, Keys> & {
    [K in Keys]-?: Required<Pick<T, K>> & Partial<Pick<T, Exclude<Keys, K>>>;
}[Keys];

type TypeAwareSdefElementConstructorArgs<Attributes, Children> = Attributes extends {
    type?: unknown;
} ? ([
    attributes: Attributes,
    children: Children & {
        types?: never;
    }
] | [
    attributes: Omit<Attributes, 'type'> & {
        type?: never;
    },
    children: Children & {
        types: Type[];
    }
]) : [
        attributes: Attributes,
        children: Children
    ];
type ConcreteSdefXMLElement =
    | AccessGroup
    | Accessor
    | Class
    | ClassExtension
    | Cocoa
    | Command
    | Contents
    | Dictionary
    | DirectParameter
    | Element
    | Enumeration
    | Enumerator
    | Event
    | Parameter
    | Property
    | RecordType
    | RespondsTo
    | Result
    | Suite
    | Synonym
    | Type
    | ValueType
    | XRef;

/**
 * Abstract base class for all .sdef XML elements.
 */

abstract class SdefXMLElement<
    Attributes extends Record<
        string,
        { toString(): string; } | undefined
    >
    = Record<never, never>,
    Children extends Record<
        string,
        | ConcreteSdefXMLElement
        | ConcreteSdefXMLElement[]
        | undefined
    >
    = Record<never, never>
> {

    /**
     * The attributes for the element.
     */
    readonly attributes: Attributes;

    /**
     * The children for the element.
     */
    readonly children: Children;

    /**
     * The XML builder for the element.
     */
    protected get builder(): XMLBuilder {
        const _builder = create().ele(this.getElementName());
        for (const [attribute, value] of Object.entries(this.attributes)) {
            if (value !== undefined) {
                _builder.att(attribute, value.toString());
            }
        }
        const ordering = this.getChildrenOrdering();
        const childKeys = Object.keys(this.children);
        const rankKey = (k: string) => {
            const i = ordering.indexOf(k);
            // if the key is not in the ordering,
            //  it should be placed at the end.
            return i === -1 ? Number.POSITIVE_INFINITY : i;
        };
        const sortedChildrenKeys = childKeys
            .map((k, orig) => ({ k, orig }))
            .sort((a, b) => (rankKey(a.k) - rankKey(b.k)) || (a.orig - b.orig))
            .map(x => x.k);
        for (const childrenKey of sortedChildrenKeys) {
            const childOrChildGroup = this.children[childrenKey];
            if (childOrChildGroup === undefined)
                continue;
            if (Array.isArray(childOrChildGroup)) {
                for (const child of childOrChildGroup) {
                    _builder
                        .import((child as SdefXMLElement).builder);
                }
            }
            else {
                _builder
                    .import((childOrChildGroup as SdefXMLElement).builder);
            }
        }
        return _builder;
    }

    /**
     * Gets the name of the element.
     */
    protected abstract getElementName(): string;

    /**
     * Gets an ordered list of the keys by which
     *  the children should be sorted.
     */
    protected abstract getChildrenOrdering():
        readonly (keyof TypeAwareSdefElementConstructorArgs<Attributes, Children>[1])[];

    /**
     * Creates a new SdefXMLElement.
     * @param builder The XML builder for the element.
     * @param attributes The attributes for the element.
     * @param children The children for the element.
     */
    constructor(...args: TypeAwareSdefElementConstructorArgs<Attributes, Children>) {
        const [attributes, children] = args;
        this.attributes = attributes as Attributes;
        this.children = children as Children;
    }
}
/**
 * An element that represents an implementation. Currently,
 * the only implementation element is <cocoa>.
 */
type Implementation = (Cocoa) & SdefXMLElement;

/**
 * Represents an <access-group> element.
 */
class AccessGroup extends SdefXMLElement<{
    identifier: string;
    access?: 'r' | 'w' | 'rw';
}> {
    getElementName() {
        return 'access-group';
    }
    getChildrenOrdering() {
        return [];
    }
}

/**
 * Represents an <accessor> element.
 */
class Accessor extends SdefXMLElement<{
    style: 'index' | 'name' | 'id' | 'range' | 'relative' | 'test';
}> {
    getElementName() {
        return 'accessor';
    }
    getChildrenOrdering() {
        return [];
    }
}

type ClassAttributes = {
    name: string;
    id?: string;
    code: string;
    hidden?: 'yes' | 'no';
    plural?: string;
    inherits?: string;
    description?: string;
};
type ClassChildren = {
    implementation?: Implementation;
    synonyms?: Synonym[];
    contents?: Contents;
    properties?: Property[];
    elements?: Element[];
    respondsTo?: RespondsTo[];
    types?: Type[];
    accessGroups?: AccessGroup[];
    xrefs?: XRef[];
};

/**
 * Represents a <class> element.
 */
class Class extends SdefXMLElement<
    ClassAttributes,
    ClassChildren
> {
    getElementName() {
        return 'class';
    }
    getChildrenOrdering() {
        return [
            'implementation',
            'accessGroups',
            'types',
        ] as const;
    }
}

/**
 * Represents a <class-extension> element.
 */
class ClassExtension extends SdefXMLElement<
    Omit<
        ClassAttributes,
        'name' | 'plural' | 'inherits' | 'code'
    >
    & {
        extends: string;
        title?: string;
    },
    Omit<ClassChildren, 'types'>
> {
    getElementName() {
        return 'class-extension';
    }
    getChildrenOrdering() {
        return [
            'implementation',
            'accessGroups',
        ] as const;
    }
}

/**
 * Represents a <cocoa> element.
 */
class Cocoa extends SdefXMLElement<
    | { class: string; }
    | { key: string; }
    | { method: string; }
    | { 'boolean-value': 'YES' | 'NO'; }
    | { 'string-value': string; }
    | { 'integer-value': number; }
    | { 'insert-at-beginning': 'yes' | 'no'; }
    | { name: string; }
> {
    getElementName() {
        return 'cocoa';
    }
    getChildrenOrdering() {
        return [];
    }
}

type CommandAttributes = {
    name: string;
    id?: string;
    code: string;
    description?: string;
    hidden?: 'yes' | 'no';
};
type CommandChildren = {
    implementation?: Implementation;
    synonyms?: Synonym[];
    directParameter?: DirectParameter;
    parameters?: Parameter[];
    result?: Result;
    accessGroups?: AccessGroup[];
    xrefs?: XRef[];
};

/**
 * Represents a <command> element.
 */
class Command extends SdefXMLElement<
    CommandAttributes,
    CommandChildren
> {
    getElementName() {
        return 'command';
    }
    getChildrenOrdering() {
        return [
            'implementation',
            'accessGroups',
            'synonyms',
            'directParameter',
            'parameters',
            'result',
            'xrefs',
        ] as const;
    }
}

/**
 * Represents a <contents> element.
 */
class Contents extends SdefXMLElement<
    Omit<PropertyAttributes, 'name' | 'code'>
    & Partial<
        Pick<
            PropertyAttributes,
            'name' | 'code'
        >
    >,
    {
        implementation?: Implementation;
        synonyms?: Synonym[];
        accessGroups?: AccessGroup[];
    }
> {
    getElementName() {
        return 'contents';
    }
    getChildrenOrdering() {
        return [
            'implementation',
            'accessGroups',
            'synonyms',
        ] as const;
    }
}

/**
 * Represents a <dictionary> element.
 */
class Dictionary extends SdefXMLElement<
    { title?: string; },
    { suites: NonEmptyArray<Suite>; }
> {
    getSdefXML(options?: Omit<XMLWriterOptions, 'format'> | undefined): string {
        const xmlBuilder = create();
        xmlBuilder.dtd({
            name: 'dictionary',
            sysID: 'file:///System/Library/DTDs/sdef.dtd'
        });
        xmlBuilder.import(this.builder);
        return xmlBuilder.end({
            format: 'xml',
            ...options,
        });
    }
    getElementName() {
        return 'dictionary';
    }
    getChildrenOrdering() {
        return [
            'suites',
        ] as const;
    }
}


/**
 * Represents a <direct-parameter> element.
 */
class DirectParameter extends SdefXMLElement<
    Omit<ParameterAttributes, 'name' | 'code' | 'hidden'>,
    Omit<ParameterChildren, 'implementation'>
> {
    getElementName() {
        return 'direct-parameter';
    }
    getChildrenOrdering() {
        return [
            'types',
        ] as const;
    }
}

/**
 * Represents an <element> element.
 */
class Element extends SdefXMLElement<
    {
        type: string;
        hidden?: 'yes' | 'no';
        access?: 'r' | 'w' | 'rw';
        description?: string;
    },
    {
        implementation?: Implementation;
        accessors?: Accessor[];
        accessGroups?: AccessGroup[];
    }
> {
    getElementName() {
        return 'element';
    }
    getChildrenOrdering() {
        return [
            'implementation',
            'accessGroups',
            'accessors',
        ] as const;
    }
}

/**
 * Represents an <enumeration> element.
 */
class Enumeration extends SdefXMLElement<
    {
        name: string;
        id?: string;
        code: string;
        description?: string;
        hidden?: 'yes' | 'no';
        inline?: number;
    },
    {
        implementation?: Implementation;
        enumerators: NonEmptyArray<Enumerator>;
        xrefs?: XRef[];
    }
> {
    getElementName() {
        return 'enumeration';
    }
    getChildrenOrdering() {
        return [
            'implementation',
        ] as const;
    }
}

/**
 * Represents an <enumerator> element.
 */
class Enumerator extends SdefXMLElement<
    {
        name: string;
        code: string;
        hidden?: 'yes' | 'no';
        description?: string;
    },
    {
        implementation?: Implementation;
        synonyms?: Synonym[];
    }
> {
    getElementName() {
        return 'enumerator';
    }
    getChildrenOrdering() {
        return [
            'implementation',
        ] as const;
    }
}

/**
 * Represents an <event> element.
 */
class Event extends SdefXMLElement<
    CommandAttributes,
    Omit<CommandChildren, 'accessGroups'>
> {
    getElementName() {
        return 'event';
    }
    getChildrenOrdering() {
        return [
            'implementation',
            'synonyms',
            'directParameter',
            'parameters',
            'result',
            'xrefs',
        ] as const;
    }
}

type ParameterAttributes = {
    name: string;
    code: string;
    hidden?: 'yes' | 'no';
    type?: string;
    optional?: 'yes' | 'no';
    'requires-access'?: 'r' | 'w' | 'rw';
    description?: string;
};
type ParameterChildren = {
    implementation?: Implementation;
};

class Parameter extends SdefXMLElement<
    ParameterAttributes,
    ParameterChildren
> {
    getElementName() {
        return 'parameter';
    }
    getChildrenOrdering() {
        return [
            'implementation',
        ] as const;
    }
}

type PropertyAttributes = {
    name: string;
    code: string;
    hidden?: 'yes' | 'no';
    type?: string;
    access?: 'r' | 'w' | 'rw';
    'in-properties'?: 'yes' | 'no';
    description?: string;
};

/**
 * Represents a <property> element.
 */
class Property extends SdefXMLElement<
    PropertyAttributes,
    {
        implementation?: Implementation;
        synonyms?: Synonym[];
        accessGroups?: AccessGroup[];
    }
> {
    getElementName() {
        return 'property';
    }
    getChildrenOrdering() {
        return [
            'implementation',
            'accessGroups',
        ] as const;
    }
}

/**
 * Represents a <record-type> element.
 */
class RecordType extends SdefXMLElement<
    {
        name: string;
        id?: string;
        code: string;
        hidden?: 'yes' | 'no';
        plural?: string;
        description?: string;
    },
    {
        implementation?: Implementation;
        synonyms?: Synonym[];
        properties: NonEmptyArray<Property>;
        xrefs?: XRef[];
    }
> {
    getElementName() {
        return 'record-type';
    }
    getChildrenOrdering() {
        return [
            'implementation',
            'synonyms',
        ] as const;
    }
}

/**
 * Represents a <responds-to> element.
 */
class RespondsTo extends SdefXMLElement<
    {
        command: string;
        hidden?: 'yes' | 'no';
        name?: string;
    },
    {
        implementation?: Implementation;
        accessGroups?: AccessGroup[];
    }
> {
    getElementName() {
        return 'responds-to';
    }
    getChildrenOrdering() {
        return [
            'implementation',
            'accessGroups',
        ] as const;
    }
}
/**
 * Represents a <result> element.
 */

class Result extends SdefXMLElement<
    Pick<
        ParameterAttributes,
        'type' | 'description'
    >
> {
    getElementName() {
        return 'result';
    }
    getChildrenOrdering() {
        return [];
    }
}

type SuiteMembers = {
    classes?: NonEmptyArray<Class>;
    extensions?: NonEmptyArray<ClassExtension>;
    commands?: NonEmptyArray<Command>;
    enumerations?: NonEmptyArray<Enumeration>;
    events?: NonEmptyArray<Event>;
    recordTypes?: NonEmptyArray<RecordType>;
    valueTypes?: NonEmptyArray<ValueType>;
};
type SuiteChildren = {
    implementation?: Implementation;
    accessGroups?: AccessGroup[];
} & RequireAtLeastOne<SuiteMembers, keyof SuiteMembers>;

/**
 * Represents a <suite> element.
 */
class Suite extends SdefXMLElement<
    {
        name: string;
        code: string;
        description?: string;
        hidden?: 'yes' | 'no';
    },
    SuiteChildren
> {
    getElementName() {
        return 'suite';
    }
    getChildrenOrdering() {
        return [
            'implementation',
            'accessGroups',
        ] as const;
    }
}

type SynonymAttributes = RequireAtLeastOne<{
    name?: string;
    code?: string;
    hidden?: 'yes' | 'no';
    plural?: string;
}, 'name' | 'code'>;

/**
 * Represents a <synonym> element.
 */
class Synonym extends SdefXMLElement<
    SynonymAttributes,
    { implementation?: Implementation; }
> {
    getElementName() {
        return 'synonym';
    }
    getChildrenOrdering() {
        return [
            'implementation',
        ] as const;
    }
}

/**
 * Represents a <type> element.
 */
class Type extends SdefXMLElement<
    {
        type: string;
        list?: 'yes' | 'no';
        hidden?: 'yes' | 'no';
    },
    { types?: never; }
> {
    getElementName() {
        return 'type';
    }
    getChildrenOrdering() {
        return [];
    }
}

/**
 * Represents a <value-type> element.
 */
class ValueType extends SdefXMLElement<
    {
        name: string;
        id?: string;
        code: string;
        hidden?: 'yes' | 'no';
        plural?: string;
        description?: string;
    },
    {
        implementation?: Implementation;
        synonyms?: Synonym[];
        xrefs?: XRef[];
    }
> {
    getElementName() {
        return 'value-type';
    }
    getChildrenOrdering() {
        return [
            'implementation',
        ] as const;
    }
}

/**
 * Represents a <xref> element.
 */
class XRef extends SdefXMLElement<
    {
        target: string;
        hidden?: 'yes' | 'no';
    }
> {
    getElementName() {
        return 'xref';
    }
    getChildrenOrdering() {
        return [];
    }
}
export {
    type Implementation,
    SdefXMLElement,
    AccessGroup,
    Accessor,
    Class,
    ClassExtension,
    Cocoa,
    Command,
    Contents,
    Dictionary,
    DirectParameter,
    Element,
    Enumeration,
    Enumerator,
    Event,
    Parameter,
    Property,
    RecordType,
    RespondsTo,
    Result,
    Suite,
    Synonym,
    Type,
    ValueType,
    XRef,
};
