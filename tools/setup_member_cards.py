#!/usr/bin/env python3
"""Launch the five First Scene cards on the configured RESCENE testnet project.

Durable, exact Engine requests and stable idempotency keys recover lost replies.
Requires --execute; never changes a player account or buys from a listing.
"""
import argparse, base64, fcntl, json, time, urllib.request
from pathlib import Path
import setup_energy_drink as engine

ROOT = Path(__file__).resolve().parents[1]
RECORD = ROOT / 'contracts/deployments/member-card-listings.json'
MEMBERS = ['Woni', 'Liv', 'Minami', 'May', 'Zena']

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--execute', action='store_true')
    args = parser.parse_args()
    if not args.execute:
        print('Five First Scene ERC-1155 cards; token/listing IDs 1–5; 10,000 each; 450 STARL each. Use --execute to submit.')
        return
    assert engine.MANIFEST['chainId'] == 421614
    assert engine.MANIFEST['engineProjectId'] == '7fe1ecf2-b715-43bc-ba03-3f0a1149bc5d'
    lock = RECORD.with_suffix('.lock').open('w')
    fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    state = json.loads(RECORD.read_text()) if RECORD.exists() else {'chainId':421614,'cards':[], 'steps':{}}
    if state.get('status') == 'confirmed':
        print('First Scene launch already confirmed. No mint or listing submissions made.')
        return
    def save():
        temp = RECORD.with_suffix('.tmp'); temp.write_text(json.dumps(state, indent=2)+'\n'); temp.replace(RECORD)
    def write(step, address, method, arguments, abi):
        if step not in state['steps']:
            state['steps'][step] = {'key':'rescene/first-scene-launch/'+step+'/v1', 'request':{
                'chainId':421614,'contractAddress':address,'walletAddress':engine.TREASURY,
                'functionName':method,'args':arguments,'abi':engine.function(abi,method),'value':'0'}}
            save()
        current = state['steps'][step]
        if 'id' not in current:
            response = engine.call('/v1/contracts/write',current['request'],{**engine.HEAD,'Idempotency-Key':current['key']})['transaction']
            current['id'] = response['id']; save()
        for _ in range(60):
            tx = engine.call('/v1/transactions/'+current['id'])['transaction']
            assert tx['appId'] == engine.MANIFEST['engineProjectId'] and tx['chainId'] == 421614
            assert tx['contractAddress'].lower() == address.lower() and tx['method'] == method and tx['args'] == current['request']['args']
            current['status'] = tx['status']; current['transactionHash'] = tx.get('transactionHash',''); save()
            if tx['status'] == 'confirmed': print(step, 'confirmed',current['transactionHash'],flush=True); return
            if tx['status'] == 'failed': raise RuntimeError('Inspect failed Engine transaction '+current['id']+' before changing anything')
            time.sleep(2)
        raise RuntimeError('Still pending. Rerun resumes the same Engine transaction.')
    for index, member in enumerate(MEMBERS, 1):
        image = 'https://engine.fluentxverse.com/items/cards/'+member.lower()+'.jpg'
        with urllib.request.urlopen(urllib.request.Request(image,headers={'User-Agent':'Mozilla/5.0'}),timeout=20) as response:
            assert response.headers.get_content_type() == 'image/jpeg'
        metadata = {'name':member+' · First Scene','description':member+' from the First Scene collection. A cosmetic RESCENE Rhythm member card for your profile and stage HUD.', 'image':image,
            'attributes':[{'trait_type':'Member','value':member},{'trait_type':'Series','value':'First Scene'},{'trait_type':'Rarity','value':'SR'},{'trait_type':'Type','value':'Member card'},{'trait_type':'Cosmetic','value':'Yes'}]}
        uri = 'data:application/json;base64,'+base64.b64encode(json.dumps(metadata,separators=(',',':')).encode()).decode()
        card = {'id':f'scene_{index:02}','member':member,'tokenId':str(index),'listingId':str(index),'price':'450','priceRaw':str(450*10**18),'initialStock':10000,'metadata':metadata,'metadataURI':uri}
        if len(state['cards']) < index: state['cards'].append(card); save()
        else: assert state['cards'][index-1] == card, 'Metadata changed after submission; inspect launch record'
        step = member.lower()+'-mint'
        if step not in state['steps']: assert engine.read(engine.COLLECTION,'nextTokenIdToMint',[],engine.NFT) == str(index), 'Unexpected collection token ID'
        write(step,engine.COLLECTION,'mintTo',[engine.TREASURY,str(2**256-1),uri,'10000'],engine.NFT)
        assert engine.read(engine.COLLECTION,'balanceOf',[engine.TREASURY,str(index)],engine.NFT) == '10000'
        step = member.lower()+'-listing'
        if step not in state['steps']: assert engine.read(engine.MARKET,'totalListings',[],engine.LIST) == str(index), 'Unexpected listing ID'
        params = state.setdefault('listingParameters',{}).setdefault(member,{'assetContract':engine.COLLECTION,'tokenId':str(index),'quantity':'10000','currency':engine.TOKEN,'pricePerToken':str(450*10**18),'startTimestamp':str(int(time.time())),'endTimestamp':'2082758400','reserved':False})
        save()
        write(step,engine.MARKET,'createListing',[json.dumps(params,separators=(',',':'))],engine.LIST)
        card['verifiedListing'] = engine.read(engine.MARKET,'getListing',[str(index)],engine.LIST)
        # Keep stable metadata separate from changing chain verification.
        state.setdefault('verifiedListings',{})[str(index)] = card.pop('verifiedListing'); save()
    state['status'] = 'confirmed'; save()
    print('Five real First Scene cards minted and listed for 450 STARL each.',flush=True)

if __name__ == '__main__': main()
