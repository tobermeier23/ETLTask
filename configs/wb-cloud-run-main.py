import functions_framework
import zipfile
from urllib.request import urlretrieve

@functions_framework.http
def hello_http(request):
    """HTTP Cloud Function.
    Args:
        request (flask.Request): The request object.
        <https://flask.palletsprojects.com/en/1.1.x/api/#incoming-request-data>
    Returns:
        The response text, or any set of values that can be turned into a
        Response object using `make_response`
        <https://flask.palletsprojects.com/en/1.1.x/api/#flask.make_response>.
    """
    request_json = request.get_json(silent=True)
    request_args = request.args

    if request_json and 'name' in request_json:
        name = request_json['name']
    elif request_args and 'name' in request_args:
        name = request_args['name']
    else:
        name = 'World'
    return 'Hello {}!'.format(name)

url = "https://api.worldbank.org/v2/en/indicator/SP.DYN.LE00.IN?downloadformat=csv"
filename = "/wbfiles/wb_input.zip"
wbextract_path = "/wbfiles"

urlretrieve(url, filename)
with zipfile.ZipFile(filename, 'r') as zip_ref:
    zip_ref.extractall(wbextract_path)
