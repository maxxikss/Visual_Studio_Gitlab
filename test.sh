#!/bin/bash
#env
http_proxy=""
HTTP_PROXY=""
https_proxy=""
HTTPS_PROXY=""
echo 'UC;Conversation ID;Start node;Expected flow;Real flow;Test result' > report.csv

#TODO
# - rozchodit
# - dokumentace pro business
# - validace pro UCNAME je nutnost
# - více utterances pro jeden test pro převzetí proměnných z callů
# - linux tým (jq, colordiff)
# - namyslet jak by mohl business spouštět testy a definovat jen pro konkrétní vavirty


declare -A UC
declare -A UCNAME
#CZ
if [ "$(hostname)" = "vavirt2b" ]; then
  UC['UC20CZ']="8141"
  UCNAME['UC20CZ']="UC20CZ-Light"
  UC['UC33CZ']="8121"
  UCNAME['UC33CZ']="tmcz-uc33-2012.03"
fi

if [ "$(hostname)" = "vavirt2d" ]; then
  UC['UC20SK']="8117"
  UCNAME['UC20SK']="tmsk-uc20-2009.07"
  UC['UCFINSK']="8321"
  UCNAME['UCFINSK']="FIN_sk_voice"
fi

if [ "$(hostname)" = "vavirt2a" ]; then
  UC['UC33SK-THD-CHAT']="8221"
  UCNAME['UC33SK-THD-CHAT']="UC33 chat sk"
fi

if [ "$(hostname)" = "vavirt2c" ]; then
  UC['UC33-p34']="9034"
  UCNAME['UC33-p34']="VA_ST_UC33CH"
  UC['UCINCREMENT']="8321"
  UCNAME['UCINCREMENT']="tmsk-uc20-2013.1"
fi

if [ "$(hostname)" = "vavirt2" ]; then
  UC['UC06bCZ']="9006"
  UCNAME['UC06bCZ']="tmcz-uc06b"
  #SK
  UC['UC19']="9000"
  UCNAME['UC19']="tmsk-uc19"
fi


conversationId="voice_~TEST~$RANDOM~$(date +%s)"

while IFS=';' read -r myUc startPoint expectedOutput utterance namedEntities; do
    namedEntitiesEscaped=$(echo "$namedEntities" | sed 's/"/\\"/g')

    expectedOutput=$(echo "$expectedOutput" | sed 's/"//g')
    if ! [[ "${UC[$myUc]+exists}" ]]; then
      continue
    fi
    # GET config_hash
    CFGHASH=$(curl -s --request GET --url "http://0.0.0.0:${UC[$myUc]}/projects" | grep -o "\"${UCNAME[$myUc]}\".\{100\}" | grep -o "\"nlu_model_hash\".\{34\}" | cut -c 19-)
    # GET nlu_model_hash
    CFGHASH=$(curl -s --request GET --url "http://0.0.0.0:${UC[$myUc]}/projects" | grep -o ".\{200\}\"${UCNAME[$myUc]}\"" | grep -o ".\{66\}\"description\"" | head -c 64)


    curl -sS --request PUT \
      --url http://0.0.0.0:${UC[$myUc]}/flows/$CFGHASH/conversations/$conversationId/states \
      --header 'Content-Type: application/json' \
      --data '{"channel_id": "text","named_entities": {'"${namedEntities}"'},"user_id": "","new_state": "'$startPoint'"}' --output /dev/null

    IFS='/' read -ra utteranceArray <<< "$utterance"

    # Procházíme jednotlivé utterances a posíláme je
    first=true
    for utterance in "${utteranceArray[@]}"; do

      output=$(curl -sS -X POST --header "Content-Type: application/json" http://0.0.0.0:${UC[$myUc]}/flows/$CFGHASH/conversations/$conversationId/messages -d '{"utterance": "'"$utterance"'"}' 2> /dev/null)
          # Najde řádek obsahující řetězec "intent_path" a ořízne
      output=$(echo "$output" | grep -o '"intent_path":[^]]*' | sed 's/"intent_path":\[//')
      if [ "$first" = true ]; then
        outputFinal+="$output"
        first=false
      else
        outputFinal+=",$output"
      fi

    done


    if [ "$outputFinal" != "$expectedOutput" ]; then
        echo "No match: $outputFinal"
        echo "Difference:"
        diff <(printf "%s\n" "$expectedOutput") <(printf "%s\n" "$outputFinal")
        echo "$myUc;$conversationId;$startPoint;$expectedOutput;$outputFinal;No match" >> report.csv
    else
        echo "Match: $outputFinal"
        echo "$myUc;$conversationId;$startPoint;$expectedOutput;$outputFinal;Match" >> report.csv
    fi
    echo "------------------------------"
done < test.csv



#START EMAIL
#!/bin/bash
to="ladislav.balon@external.t-mobile.cz"
subject="Report z testingu"
body="Report z testingu je v priloze tohoto emailu"
attachment="report.csv"

# Vytvoření emailového souboru
{
  echo "To: $to"
  echo "Subject: $subject"
  echo "Content-Type: multipart/mixed; boundary=\"boundary-$(date +%s)\""
  echo ""
  echo "--boundary-$(date +%s)"
  echo "Content-Type: text/plain; charset=\"UTF-8\""
  echo ""
  echo "$body"
  echo ""
  echo "--boundary-$(date +%s)"
  echo "Content-Type: application/octet-stream"
  echo "Content-Disposition: attachment; filename=\"$attachment\""
  echo ""
  cat "$attachment"
  echo ""
  echo "--boundary-$(date +%s)--"
} > email.txt

# Odeslání emailu
/usr/sbin/sendmail -t < email.txt
#STOP EMAIL

