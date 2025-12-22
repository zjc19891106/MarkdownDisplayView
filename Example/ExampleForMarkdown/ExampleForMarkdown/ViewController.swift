//
//  ViewController.swift
//  ExampleForMarkdown
//
//  Created by 朱继超 on 12/15/25.
//

import UIKit
import MarkdownDisplayView

class ViewController: UIViewController {

    private lazy var syncButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Sync MarkdownView Demo", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 18, weight: .medium)
        button.addTarget(self, action: #selector(openSyncDemo), for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private lazy var streamingButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Streaming MarkdownView Demo", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 18, weight: .medium)
        button.addTarget(self, action: #selector(openStreamingDemo), for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private lazy var tableViewButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("TableView Streaming Demo", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 18, weight: .medium)
        button.addTarget(self, action: #selector(openTableViewDemo), for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        DispatchQueue.global().async {
            FontLoader.ensureFontsRegistered()
        }
        let titleLabel = UILabel()
        titleLabel.font = .systemFont(ofSize: 18, weight: .semibold)
        titleLabel.text = "MarkdownDisplayKit Demo"
        titleLabel.backgroundColor = .systemBackground
        view.addSubview(titleLabel)
        view.addSubview(syncButton)
        view.addSubview(streamingButton)
        view.addSubview(tableViewButton)
        NSLayoutConstraint.activate([
            titleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            titleLabel.heightAnchor.constraint(equalToConstant: 44),

            syncButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            syncButton.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -60),

            streamingButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            streamingButton.topAnchor.constraint(equalTo: syncButton.bottomAnchor, constant: 20),

            tableViewButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            tableViewButton.topAnchor.constraint(equalTo: streamingButton.bottomAnchor, constant: 20)

        ])
    }

    @objc private func openSyncDemo() {
        let vc = MarkdownExampleViewController()
        vc.modalPresentationStyle = .fullScreen
        self.present(vc, animated: true, completion: nil)
    }

    @objc private func openStreamingDemo() {
        let vc = StreamingMarkdownController()
        vc.modalPresentationStyle = .fullScreen
        self.present(vc, animated: true, completion: nil)
    }

    @objc private func openTableViewDemo() {
        let vc = TableViewStreamingViewController()
        vc.modalPresentationStyle = .fullScreen
        self.present(vc, animated: true, completion: nil)
    }

}


