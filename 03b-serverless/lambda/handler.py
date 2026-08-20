import json
import boto3

dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table('serverless-items')

def handler(event, context):
    if event['httpMethod'] == 'POST':
        body = json.loads(event['body'])
        table.put_item(Item=body)
        return {'statusCode': 200, 'body': json.dumps({'message': 'Item created'})}

    if event['httpMethod'] == 'GET':
        item_id = event['queryStringParameters']['id']
        response = table.get_item(Key={'id': item_id})
        return {'statusCode': 200, 'body': json.dumps(response.get('Item', {}))}

    return {'statusCode': 400, 'body': json.dumps({'error': 'Unsupported method'})}
