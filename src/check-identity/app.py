import re
import json

# Define regex patterns
ssn_regex = r'^\d{3}-?\d{2}-?\d{4}$'
email_regex = r'^[a-zA-Z0-9._-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,4}$'

def lambda_handler(event, context):
    ssn = event.get('ssn')
    email = event.get('email')
    
    print(f"SSN: {ssn} and email: {email}")
    
    # Use re.match() to test the regex patterns
    approved = (re.match(ssn_regex, ssn) is not None and 
                re.match(email_regex, email) is not None)
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'approved': approved,
            'message': f"identity validation {'passed' if approved else 'failed'}"
        })
    }
