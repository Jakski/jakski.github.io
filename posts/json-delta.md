JSON became de facto standard for structured documents in modern days. While it
may not be used everywhere, most of times we're able to convert a document into
JSON and use a vast collection of tools to manipulate data this way.

# What about YAML?

I'll focus only on working with JSON, but YAML format is usually preferred to
represent JSON compatible schemas in more human readable way. Unless YAML
document uses some user-defined types, we can convert it to JSON e.g. using
shell function and Python module `ruamel.yaml`:

```
yaml2json () { python3 -c 'from ruamel import yaml; import json, sys; json.dump(yaml.safe_load(sys.stdin), sys.stdout)'; }
```

# Simple delta

That's the easiest case. Let's say that our first document looks like this:

```json
{
  "object1": {
    "key1": "value1",
    "key2": "value2"
  }
}
```

and our second object looks like this:

```json
{
  "object1": {
    "key2": "value2",
    "key1": "value1"
  }
}
```

When we try to create a delta normal way we get some misleading information:

```
$ diff d1.json d2.json
3,4c3,4
<     "key1": "value1",
<     "key2": "value2"
---
>     "key2": "value2",
>     "key1": "value1"
```

It's true that these documents differ in key ordering, but that's not what we
care about in structured documents. Fortunately `jq` helps here:

```
$ diff <(jq --sort-keys . d1.json) <(jq --sort-keys . d2.json)
$
```

Now we're comparing actual content, not the formatting of documents.

# Documents with changes in objects and arrays

Simple delta will work great for documents where only simple values differ.
Delta becomes less readable the more complex structures we're comparing. Let's
say our first document is now:

```json
{
  "object1": {
    "key1": "value1",
    "key2": "value2"
  },
  "object3": {
    "key1": [
      "value1",
      "value2",
      [
        {
          "key1": "value1"
        },
        {
          "key1": "value1"
        }
      ]
    ]
  }
}
```

and our second document is:

```json
{
  "object2": {
    "key1": "value1",
    "key2": "value2"
  },
  "object3": {
    "key3": [
      "value3",
      "value5",
      [
        {
          "key1": "value2"
        }
      ]
    ]
  },
  "array1": [
    "value1"
  ]
}
```

Using `diff` with `jq` still works, but now delta also contains lines which
doesn't introduce any value and are only required to ensure document validity
like curly opening and closing braces:

```
$ diff <(jq --sort-keys . d1.json) <(jq --sort-keys . d2.json)
2c2,5
<   "object1": {
---
>   "array1": [
>     "value1"
>   ],
>   "object2": {
7,9c10,12
<     "key1": [
<       "value1",
<       "value2",
---
>     "key3": [
>       "value3",
>       "value5",
12,15c15
<           "key1": "value1"
<         },
<         {
<           "key1": "value1"
---
>           "key1": "value2"
```

## Converting JSON into a "flat" form

In order to focus only on actual differences between documents and not care
about how they are formatted we will first produce a flat version of JSON where
each line corresponds to exactly one value. `jq` allows to write longer scripts
and reference them in invocations. We're going to use the following:

```
paths as $path
| getpath($path) as $value
| ($value | type) as $type
| select(
  (
    ($type == "object" and $value != {})
    or ($type == "array" and $value != [])
  )
  | not
)
| [([$path[] | tostring] | join(".")), $value]
```

It basically traverses all paths in document and outputs their value, unless
they are non-empty complex types. Let's have it convert an example document
like:

```json
{
  "empty_object": {},
  "empty_array": [],
  "array": [
    "value1",
    "value2"
  ],
  "object": {
    "key1": "value1\nvalue1.1",
    "key2": "value2"
  }
}
```

We will use `-c` option to `jq` in order to ensure that each key-value pair
actually takes one line:

```
$ cat d3.json | jq -cf flat.jq
["empty_object",{}]
["empty_array",[]]
["array.0","value1"]
["array.1","value2"]
["object.key1","value1\nvalue1.1"]
["object.key2","value2"]
```

Now we can use this `jq` script to compare more complex documents:

```
$ diff <(jq -cf flat.jq d1.json | sort) <(jq -cf flat.jq d2.json | sort)
1,6c1,6
< ["object1.key1","value1"]
< ["object1.key2","value2"]
< ["object3.key1.0","value1"]
< ["object3.key1.1","value2"]
< ["object3.key1.2.0.key1","value1"]
< ["object3.key1.2.1.key1","value1"]
---
> ["array1.0","value1"]
> ["object2.key1","value1"]
> ["object2.key2","value2"]
> ["object3.key3.0","value3"]
> ["object3.key3.1","value5"]
> ["object3.key3.2.0.key1","value2"]>>
```

# Showing only the common parts of documents

Let's say we have document:

```json
{
  "object1": {
    "key1": "value1",
    "key2": "value2.1"
  },
  "array1": [
    "value1",
    "value2",
    "value3",
    "value4"
  ]
}
```

and:

```json
{
  "object1": {
    "key1": "value1",
    "key2": "value2"
  },
  "array1": [
    "value1",
    "value2",
    "value4"
  ]
}
```

`comm` tool will help us here:

```
$ comm -1 -2 <(jq -cf flat.jq d1.json | sort) <(jq -cf flat.jq d2.json | sort)
["array1.0","value1"]
["array1.1","value2"]
["object1.key1","value1"]
```

One way to use this technique is, if we have default values files and overrides
files and want to see which keys are redundant in the latter.
