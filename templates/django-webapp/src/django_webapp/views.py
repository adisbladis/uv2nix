from django.http import HttpResponse, HttpRequest


def index(_request: HttpRequest) -> HttpResponse:
    return HttpResponse("Hello from index".encode())
