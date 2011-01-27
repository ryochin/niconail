#!/bin/sh

PLACK_SERVER=Standalone plackup -R lib --port 8450 ./app/niconail.psgi

