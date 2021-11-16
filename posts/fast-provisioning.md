WORK IN PROGRESS!

.. title: Fast sandbox provisioning
.. date: 2020-10-15 18:32:00 UTC+02:00
.. tags: nodejs webdev
.. author: Jakub Pieńkowski

Setting up environment for web development from scratch can be a daunting task,
especially for people not used to operating their workstation like yet another
node in their infrastructure. People try to solve this problem in various ways,
just to mention some of them:

Virtual machine image with whole application provisioned and ready to handle
code

   This approach works well, if you can teach developers to work with virtual
   machine managers and have beefy enough workstations. While it's not the
   fastest solution, it remains the easiest for newcommers thanks to
   technologies like VirtualBox. Of course this approach doesn't scale well,
   since aforementioned image needs to be distributed to everyone and chances
   are it's nowhere near being lightweight.

Container image

   As far as we consider Docker, Podman, systemd-nspawn and related technologies
   this is one of the easiest ways to start working on code. As long as one's
   desperate enough to spend a few hours to write friendly Docker Compose file,
   setting up a new development environment will be a matter of minutes(and why
   not reuse it as a blueprint for other projects?). That being said containers
   are not first-class citizens on any platform, hence they're implemented
   diffrently across mainstream operating systems and sometimes impose
   performance limitations. While it's usually not a problem, they tend to be
   easily exploitable as well(e.g.: Docker management socket means user have
   sudoless access to whole system).

Instructions for manual installation

   Probably the laziest and most often taken approach. It basically means that
   we provide our developers nothing except application's code and some hints on
   how to install everything and run tests. It's probably the most unreliable
   and cumbersome option, since it's natural for humans to make errors.
   Additionally this approach might totally push off newcommers on their first
   day.

Cloud environments

   By *cloud* I don't mean that they must be hosted on some public cloud
   provider. I mean ready to use environments managed by other companies or
   internal departments. They are often implemented as part of continuous
   integration system and allow developer to jump directly into working with
   code, without any preparation(except code editor of course). This approach
   works great, but requires careful design of integration pipelines and paying
   someone for hosting. Properly implemented it can be even better then local
   containers, since there's the least space for human error.

The last option has some potential for scaling up in dynamic environments, where
developer needs to constantly switch between projects and provide small, yet
visible changes in a working product. Managed development environments are also
approachable way for operations/administrators to work with developers and solve
many deployment related issues in non-critical infrastructure, before changes
get deployed.

Designing cheap cloud development environment from scratch
================================================================================

I'm not going to get into details nor provide a production ready solution, but
let's review available technologies and try to implement approachable solution
for developing web applications in NodeJS.
