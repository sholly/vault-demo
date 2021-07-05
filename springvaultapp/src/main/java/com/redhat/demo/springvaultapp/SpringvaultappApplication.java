package com.redhat.demo.springvaultapp;

import org.apache.juli.logging.Log;
import org.apache.juli.logging.LogFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestMethod;
import org.springframework.web.bind.annotation.RestController;

import javax.annotation.PostConstruct;
import java.io.File;
import java.io.FileReader;
import java.io.IOException;
import java.util.Properties;

@SpringBootApplication
@RestController
public class SpringvaultappApplication {

    private Log log = LogFactory.getLog(SpringvaultappApplication.class);

    String password;

    @Value("${VAULT_USERROLE:test}")
    String application;
    public static void main(String[] args) {
        SpringApplication.run(SpringvaultappApplication.class, args);
    }

    @PostConstruct
    private void postConstruct() {
        log.info("--------------Loading properties from " + "/tmp/" + application + ".properties");

        Properties myProps = new Properties();

        try {
            myProps.load(new FileReader(new File("/tmp/" + application + ".properties" )));
        } catch (IOException e) {
            e.printStackTrace();
        }

        password = myProps.getProperty("password");
        log.info("The password is: " + password);
    }

    @RequestMapping(value = "/secret", method = RequestMethod.GET)
    public String getSecret() {
        return password;
    }

}
