This post is rather a cheatsheet with examples than curl guide. There's a lot of
CLI REST tools available for described situations, but `curl` is probably the
most common one.

# Formatting responsess

If you want to see well-formatted JSON responses, then
[jq](https://stedolan.github.io/jq/) is a tool you're looking for. You need only
to pipe `curl` output to it.

# Using configuration file

Sometimes you need to specify a lot of HTTP headers and *curl* parameters on
every request, when you're testing some feature. Having it all on command-line
might decrease readability. Remember that you can save common options(e.g.: per
project) in configuration file and reuse them later. Let's say that you need
some configuration for interacting with Elasticsearch REST API.

*curl* configuration file(*tst.conf*):

```
header = "Content-Type: application/json"
silent
show-error
location
```

JSON payload(*tst.json*):

```
{
  "settings": {
    "index": {
      "number_of_shards": 1,
      "number_of_replicas": 1
    }
  }
}
```

Usage:

```
$ curl -K tst.conf -X PUT "$URL/index1" -d @tst.json | jq
{
  "acknowledged": true,
  "shards_acknowledged": true,
  "index": "index1"
}
```


# Filtering data from responses

*jq* can do much more than formatting JSON. It can also construct output
documents and filter fields. Let's say that we want to list Elasticsearch
indices with their corresponding versions.

Response without filter:

```
$ curl -K tst.conf -X GET "$URL/*" | jq
{
  "index1": {
    "aliases": {},
    "mappings": {},
    "settings": {
      "index": {
        "creation_date": "1558867477524",
        "number_of_shards": "1",
        "number_of_replicas": "1",
        "uuid": "BrZ7xSPfRqOK3dMFEkrzWw",
        "version": {
          "created": "7010099"
        },
        "provided_name": "index1"
      }
    }
  },
  "index2": {
    "aliases": {},
    "mappings": {},
    "settings": {
      "index": {
        "creation_date": "1558867998439",
        "number_of_shards": "1",
        "number_of_replicas": "1",
        "uuid": "P3UHaYpOQ-62HjPKOE1LPQ",
        "version": {
          "created": "7010099"
        },
        "provided_name": "index2"
      }
    }
  },
  "index3": {
    "aliases": {},
    "mappings": {},
    "settings": {
      "index": {
        "creation_date": "1558868001868",
        "number_of_shards": "1",
        "number_of_replicas": "1",
        "uuid": "_1wbEzRzRAyNQLkmD7_ctg",
        "version": {
          "created": "7010099"
        },
        "provided_name": "index3"
      }
    }
  }
}
```


Selecting data we want to see:

```
$ curl -K tst.conf -X GET "$URL/*" | jq 'to_entries[] | {index: .key, version: .value.settings.index.version }'
{
  "index": "index1",
  "version": {
    "created": "7010099"
  }
}
{
  "index": "index2",
  "version": {
    "created": "7010099"
  }
}
{
  "index": "index3",
  "version": {
    "created": "7010099"
  }
}
```

# Embedding long string in GET queries

Most HTTP servers limit size of HTTP line, yet carrying ~100 characters long
string around is error prone. Placing it directly in *curl* parameter may lead
to unexpected behaviour, when you forget to properly encode some characters. We
can work around this problem by using *-G* and *--data-urlencode* options with
*curl*. Let's say that we want to use Elasticsearch scroll.

Example query(*tst.json*):

```
{
  "size": 1,
  "query": {
    "match_all": {}
  }
}
```

Create scroll and store ID without new line:

```
$ curl -K tst.conf -X POST "$URL/_search?scroll=10m" -d @tst.json | jq -r '._scroll_id' | tr -d '\n' > scroll_id.txt
```


Retrieve results from scroll:

```
$ curl -K tst.conf -GX GET "$URL/_search/scroll" --data-urlencode "scroll_id@scroll_id.txt" | jq
{
  "took": 6,
  "timed_out": false,
  "_shards": {
    "total": 1,
    "successful": 1,
    "skipped": 0,
    "failed": 0
  },
  "hits": {
    "total": {
      "value": 0,
      "relation": "eq"
    },
    "max_score": null,
    "hits": []
  }
}
```
