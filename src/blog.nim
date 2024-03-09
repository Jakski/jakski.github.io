import std/[
  streams,
  tables,
  os,
  sequtils,
  strutils,
  algorithm,
]
import yaml
import markdown
from htmlgen as h import nil

type
  Post = object
    title: string
    date: string
  Config = object
    posts: Table[string, Post]
    outputDir: string

func asHTML(s: string): string =
  s
    .replace("&", "&amp;")
    .replace("<", "&lt;")
    .replace(">", "&gt;")
    .replace("\"", "&quot;")

func renderPostItem(name: string, config: Config, post: Post): string =
  h.li(
    class="posts-list-item",
    h.a(href=(config.outputDir & "/posts/" & name & ".html"), post.title.asHTML),
    h.time(datetime=post.date, "[" & post.date.asHTML & "]")
  )

proc renderPosts(config: Config) =
  for slug, post in config.posts.pairs:
    let output = open(config.outputDir & "/posts/" & slug & ".html", fmWrite)
    output.writeLine("<!DOCTYPE html>")
    output.write(h.html(
      lang="en",
      h.head(
        h.meta(charset="utf-8"),
        h.meta(name="viewport", content="width=device-width, initial-scale=1"),
        h.link(rel="stylesheet", href="/style.css"),
        h.title("Jakski".asHTML),
      ),
      h.body(
        h.h1(id="title", h.a(href="/", "Jakski's blog")),
        h.header(
          h.h1(id="post-title", post.title.asHTML),
          h.time(id="post-date", datetime=post.date, post.date.asHTML),
        ),
        markdown(readFile("posts/" & slug & ".md"))
      )
    ))
    output.close()

proc renderMainPage(config: Config) =
  let output = open(config.outputDir & "/index.html", fmWrite)
  defer: output.close()
  output.writeLine("<!DOCTYPE html>")
  output.write(h.html(
    lang="en",
    h.head(
      h.meta(charset="utf-8"),
      h.meta(name="viewport", content="width=device-width, initial-scale=1"),
      h.link(rel="stylesheet", href="/style.css"),
      h.title("Jakski's blog"),
    ),
    h.body(
      h.h1(id="title", h.a(href="/", "Jakski's blog")),
      h.ul(
        id="posts-list",
        foldl(sorted(config.posts.pairs.toSeq, proc (a, b: tuple): int = system.cmp(a[1].date, b[1].date), Descending), a & renderPostItem(b[0], config, b[1]), "")
      )
    )
  ))

when isMainModule:
  var config: Config
  var configSrc = newFileStream("config.yaml")
  yaml.load(configSrc, config)
  configSrc.close()
  if config.outputDir != ".":
    removeDir(config.outputDir)
    discard existsOrCreateDir(config.outputDir)
    copyFile("style.css", config.outputDir & "/style.css")
  discard existsOrCreateDir(config.outputDir & "/posts")
  renderMainPage(config)
  renderPosts(config)
