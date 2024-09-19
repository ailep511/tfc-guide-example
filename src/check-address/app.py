import json

def lambda_handler(event, context):
    street = event.get('street')
    city = event.get('city')
    state = event.get('state')
    zip_code = event.get('zip')
    
    print(f"Address information: {street}, {city}, {state} - {zip_code}")
    
    approved = all(item and item.strip() for item in [street, city, state, zip_code])
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'approved': approved,
            'message': f"address validation {'passed' if approved else 'failed'}"
        })
    }
