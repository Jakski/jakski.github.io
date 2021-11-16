Docker is all about caging some process sub-tree in isolated prison with
provided resources. It's quite practical to have development environment
separated in disposable containers. Problem arises, when we want to debug
something that's imprisoned. Of course we can observe logs and check status
of our containers, but sometimes the most practical thing to do is to enter our
container prison and see for ourselves how everything works inside.

# Native Docker way of entering prison(container)

Docker equips us with sub-command *exec*. It's the easiest way to enter exactly
the same environment as our imprisoned processes are using. While debugging, the
most useful *exec* you can invoke is usually interactive shell like:

```
$ docker exec -it backend_app_1 /bin/sh
```

After this we're ready to start issuing commands inside container and diagnose
further bugs. This will launch command with same user as specified in
*Dockerfile*. What, if you want e.g. to enter container as a *root*? *-u* flag
comes with help. Simply type:

```
$ docker exec -itu root backend_app_1 /bin/sh
```

and you're good to go.

# Dirty way of entering prison

As you probably already know, Linux containers are made of namespaces. They are
used to virtualise resources presented to imprisoned processes. Because they
aren't monolithic, you can enter only some of them, without being fully
imprisoned. It's useful, if you have some diagnostic tools on your host system,
which you want to invoke in your container. *docker-exec* would normally put you
inside all namespaces of running container. Tool *nsenter* will let you
explicitly choose what you want to derive from container in some process. How
you can find what namespaces to enter? You need to know only PID of running
process. Since processes in containers are visible in our process tree, you can
simply *grep* through *ps -eF* output. Let's say you are looking for container
with *uwsgi* running inside:

```
$ ps -eF | grep uwsgi
```

You should see at least one *uwsgi* process, if you're really running it. Now
let's use *nsenter* to enter it's network namespace alone:

```
$ nsenter -n -t <pid>
```

Now you're in same network namespace as imprisoned process. Note that you can
now diagnose network with all you tools from host system since you mount
namespace wasn't touched.

# Duplicating container's environment

Sometimes init script just fails without any readable reason, leaving container
crashed without any processes in it. You cannot enter inactive prison. You can of
course inspect it's environment like volumes used by it. After initial analysis
you will probably want to reproduce problem in controlled circumstances, e.g.
by invoking entrance script in already imprisoned shell. Let's say you would
like to debug crushed container *backend_app_1*:

```
$ docker ps -a --format='{{.Names}} {{.Status}}' -f "name=backend_app_1"
backend_app_1 Exited (137) 9 hours ago
```

You cannot run shell in container with this state. You save it's current state
though:

```
$ docker commit backend_app_1 backend_app:debug
```

To list all images matching tag *debug*:

```
$ docker images -f 'reference=`:debug'
REPOSITORY          TAG                 IMAGE ID            CREATED             SIZE
backend_app         debug               8185ea95bd7d        2 minutes ago       215MB
```

Now you can run this saved state with volumes from original container:

```
$ docker run -it --entrypoint /bin/sh --volumes-from backend_app_1 --name debug backend_app:debug
```

If you need some networks from original container, you can inspect it and plug
debug container like, so:

```
$ docker network connect backend_default debug
```

# Final thoughts

I've described a few methods of getting into position of imprisoned processes.
Remember that all resources used, by containers are actually visible on your
host system, so entering prison isn't always required, e.g. if you want to
diagnose you container with *strace* you don't have to enter it's namespaces.
Container's PID namespace is perfectly visible to you. If you can locate
container in you process tree, you can as well invoke *strace* passing host PID
as argument rather then installing it in container and trying to debug from
inside.
