def func_1():
    print ("good things")


def func_2():
    print ("next good things")


def my_decorator(func):
    def wrapper():
        print ("run")
        func()
        print ("finish")
    retunr wrapper
