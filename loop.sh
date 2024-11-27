#!/bin/bash

#
# When testing the admin api, the token will timeout within 15 minutes.
# You can't however get a new admin api token every time you run the script as there is a limit on how many
# the server will hand out.

# For testing and development purposes, after getting a token, put it in this script, which will poll
# the server with it every 5 minutes, keeping the token alive.

# When doing this, in the fm_install.sh script, comment out the section that gets a new token.


#token for testing
token=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzaWQiOiIxNmZhYmQ0Ni03Mjg5LTRiZDUtOGIwMy1mYzJmMjE3MWI1YTAiLCJpYXQiOjE3MzIyNjQ5ODN9.mXtwVnHBpklpqoN1trHQ5XMzAIAoKPMLMMsgnzpHt2Q
token=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzaWQiOiJiNTE0YzBhZC01YzY4LTRjMjktODVjOC0yMjNkOTVmM2JiMmUiLCJpYXQiOjE3MzIzNTY0NTJ9.0BKUFtU0i5LLYLQrScL_bLBp3GerS6eFxhWkFQEKkY8

while true
do

  #Check token works
  json=`curl -s https://$HOSTNAME/fmi/admin/api/v2/server/metadata \
   -H "Authorization: Bearer $token" \
   -H "Content-Type: application/json"`
 
  ok=`echo $json | jq --raw-output '.messages[0].text'`

  if [ "$ok" != 'OK' ]; then
    echo "Token not working"
    echo $json
    exit 9
  fi

  echo $json | jq .response.ServerHostTime
  sleep 300  # 5 minutes
done
